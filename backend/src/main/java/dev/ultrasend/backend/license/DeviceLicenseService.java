package dev.ultrasend.backend.license;

import dev.ultrasend.backend.entity.*;
import dev.ultrasend.backend.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;
import java.time.Instant;
import java.util.*;
import java.util.function.Supplier;

@Service @RequiredArgsConstructor
public class DeviceLicenseService {
    private final DeviceLicenseGrantRepository grants;
    private final DeviceLicenseAuditRepository audit;
    private final DeviceLicenseCodeRepository codes;
    private final DeviceLicenseAccountRepository accounts;
    private final DeviceLicenseMigrationRepository migration;
    private final MembershipEntitlementRepository entitlements;
    private final DeviceCredentialRepository credentials;
    private final DeviceRepository devices;
    private final dev.ultrasend.backend.service.DevicePairingService pairing;
    private final UserRepository users;
    private final LicenseCodeCodec codec;
    private final LicenseAbuseGuard guard;
    private final PlatformTransactionManager transactions;
    @Value("${app.device-license.code-ttl-seconds:600}") private long codeTtlSeconds = 600;
    @Value("${app.device-license.replacements-per-day:20}") private int replacementsPerDay = 20;
    private static final List<String> PENDING = List.of("PENDING", "CLAIMED");

    private void audit(Long owner,String action,String device,String request) {
        audit.save(DeviceLicenseAudit.builder().id(UUID.randomUUID().toString()).ownerUserId(owner)
                .action(action).deviceId(device).requestId(request).createdAt(Instant.now()).build());
    }
    private <T> T tx(Supplier<T> work) { return new TransactionTemplate(transactions).execute(s -> work.get()); }
    private void lockOwner(Long owner) { users.lockById(owner).orElseThrow(() -> error("license_account_missing")); }
    private void lockDevice(String id) { credentials.lockByDeviceId(id).orElseThrow(() -> error("license_device_missing")); }
    static ResponseStatusException error(String reason) { return new ResponseStatusException(HttpStatus.CONFLICT, reason); }
    private static String clean(String value, String fallback, int length) {
        String s = value == null || value.isBlank() ? fallback : value.strip();
        return s.substring(0, Math.min(length, s.length()));
    }
    private MembershipEntitlement entitlement(Long owner) { return entitlements.findByUserId(owner).orElse(null); }
    private boolean paid(MembershipEntitlement e) {
        if (e == null || "FREE".equalsIgnoreCase(e.getTierCode())) return false;
        return Boolean.TRUE.equals(e.getIsLifetime()) || (e.getSubscriptionExpiresAt() != null && e.getSubscriptionExpiresAt().isAfter(Instant.now()));
    }
    private int capacity(Long owner) {
        MembershipEntitlement e = entitlement(owner);
        if (!paid(e)) return 0;
        return Math.max(0, e.getDeviceLimit()) + accounts.findById(owner).map(DeviceLicenseAccount::getLegacyExtraSlots).orElse(0);
    }
    private List<DeviceLicenseGrant> bound(Long owner) { return grants.findByOwnerUserIdAndRevokedAtIsNullOrderByActivatedAtAscDeviceIdAsc(owner); }
    public int authorizedCount(Long owner) { return Math.min(capacity(owner), bound(owner).size()); }
    public int deviceCapacity(Long owner) { return capacity(owner); }
    public boolean isAuthorized(String deviceId) {
        DeviceLicenseGrant g = grants.findById(deviceId).orElse(null);
        return g != null && active(g);
    }
    private boolean active(DeviceLicenseGrant grant) {
        if (grant.getRevokedAt() != null) return false;
        List<DeviceLicenseGrant> list = bound(grant.getOwnerUserId());
        int limit = capacity(grant.getOwnerUserId());
        for (int i = 0; i < Math.min(limit, list.size()); i++) {
            if (list.get(i).getDeviceId().equals(grant.getDeviceId())) return true;
        }
        return false;
    }
    private List<DeviceLicenseCode> pending(Long owner) {
        List<DeviceLicenseCode> result = new ArrayList<>();
        for (DeviceLicenseCode c : codes.findByOwnerUserIdAndStatusInOrderByCreatedAtDesc(owner, PENDING)) {
            if (c.getExpiresAt().isAfter(Instant.now())) result.add(c);
        }
        return result;
    }
    public Map<String,Object> mine(String deviceId) {
        DeviceLicenseGrant g = grants.findById(deviceId).orElse(null);
        boolean enabled = g != null && active(g);
        MembershipEntitlement e = g == null ? null : entitlement(g.getOwnerUserId());
        String state = enabled ? "AUTHORIZED" : g == null ? "FREE" : g.getRevokedAt() != null ? "REVOKED" : paid(e) ? "SUSPENDED" : "EXPIRED";
        DeviceLicenseCode waiting = codes.findByDeviceIdAndStatusOrderByCreatedAtDesc(deviceId, "CLAIMED").stream()
                .filter(c -> c.getExpiresAt().isAfter(Instant.now())).findFirst().orElse(null);
        return map("deviceId", deviceId, "status", state, "authorized", enabled,
                "name", g == null ? null : g.getName(), "expiresAt", e == null || Boolean.TRUE.equals(e.getIsLifetime()) ? null : e.getSubscriptionExpiresAt(),
                "ownerLabel", g == null || g.getRevokedAt() != null ? null : "••••" + String.format("%04d", g.getOwnerUserId() % 10000),
                "pendingRequest", waiting == null ? null : requestView(waiting));
    }
    public Map<String,Object> dashboard(Long owner) {
        int limit = capacity(owner);
        List<DeviceLicenseGrant> all = bound(owner);
        List<Map<String,Object>> rows = new ArrayList<>();
        for (int i = 0; i < all.size(); i++) {
            DeviceLicenseGrant g = all.get(i);
            Instant seen = credentials.findByDeviceId(g.getDeviceId()).map(DeviceCredential::getLastIssuedAt).orElse(null);
            rows.add(map("deviceId",g.getDeviceId(),"name",g.getName(),"platform",g.getPlatform(),
                    "activatedAt",g.getActivatedAt(),"lastSeen",seen,"authorized",i < limit,"legacy",g.isLegacy()));
        }
        List<DeviceLicenseCode> held = pending(owner);
        return map("capacity",limit,"used",Math.min(limit,all.size()),"boundCount",all.size(),"reserved",held.size(),
                "available",Math.max(0,limit-all.size()-held.size()),"devices",rows,
                "requests",held.stream().map(this::requestView).toList());
    }
    private Map<String,Object> requestView(DeviceLicenseCode c) {
        return map("id",c.getId(),"status",c.getStatus(),"createdAt",c.getCreatedAt(),"expiresAt",c.getExpiresAt(),
                "deviceId",c.getDeviceId(),"name",c.getDeviceName(),"platform",c.getPlatform());
    }
    public Map<String,Object> issue(Long owner) {
        guard.check("issue:"+owner,30,3600000);
        for (int attempt=0; attempt<8; attempt++) {
            try { return tx(() -> {
                lockOwner(owner);
                if (capacity(owner) <= bound(owner).size() + pending(owner).size()) throw error("license_no_slots");
                String code = codec.newCode();
                String qr = codec.newQrToken();
                DeviceLicenseCode row = DeviceLicenseCode.builder().id(UUID.randomUUID().toString()).ownerUserId(owner)
                        .codeHash(codec.hash("code",code)).qrHash(codec.hash("qr",qr)).status("PENDING")
                        .createdAt(Instant.now()).expiresAt(Instant.now().plusSeconds(codeTtlSeconds)).build();
                codes.saveAndFlush(row);
                audit(owner,"ISSUED",null,row.getId());
                return map("id",row.getId(),"code",code,"qrToken",qr,"expiresAt",row.getExpiresAt());
            }); } catch (DataIntegrityViolationException collision) {
                if (attempt==7) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"license_issue_retry");
            }
        }
        throw error("license_issue_retry");
    }
    public Map<String,Object> redeem(String deviceId, String shortCode, String qrToken, String name, String platform, String ip) {
        guard.check("redeem:global",1200,60000);
        guard.check("redeem:ip:"+ip,30,60000);
        guard.check("redeem:device:"+deviceId,6,60000);
        boolean qr = qrToken != null && !qrToken.isBlank();
        DeviceLicenseCode found = (qr ? codes.findByQrHash(codec.hash("qr",qrToken))
                : codes.findByCodeHash(codec.hash("code",codec.normalize(shortCode))))
                .orElseThrow(() -> error("license_invalid_code"));
        return tx(() -> {
            lockOwner(found.getOwnerUserId());
            DeviceLicenseCode c = codes.findById(found.getId()).orElseThrow();
            if ("REDEEMED".equals(c.getStatus()) && deviceId.equals(c.getDeviceId())) return mine(deviceId);
            if (!PENDING.contains(c.getStatus()) || !c.getExpiresAt().isAfter(Instant.now())) throw error("license_invalid_code");
            if (capacity(c.getOwnerUserId()) == 0) throw error("license_membership_expired");
            if (c.getDeviceId() != null && !c.getDeviceId().equals(deviceId)) throw error("license_code_claimed");
            lockDevice(deviceId);
            DeviceLicenseGrant existing = grants.lockByDeviceId(deviceId).orElse(null);
            if (existing != null && existing.getRevokedAt() == null) throw error("license_device_already_bound");
            c.setDeviceId(deviceId);
            c.setDeviceName(clean(name,"Device",128));
            c.setPlatform(clean(platform,"unknown",32));
            if (qr) activate(c); else { c.setStatus("CLAIMED"); codes.saveAndFlush(c); audit(c.getOwnerUserId(),"CLAIMED",deviceId,c.getId()); }
            return mine(deviceId);
        });
    }
    public Map<String,Object> approve(Long owner, String requestId) {
        return tx(() -> {
            lockOwner(owner);
            DeviceLicenseCode c = ownedCode(owner,requestId);
            if ("REDEEMED".equals(c.getStatus())) return dashboard(owner);
            if (!"CLAIMED".equals(c.getStatus()) || !c.getExpiresAt().isAfter(Instant.now())) throw error("license_invalid_code");
            lockDevice(c.getDeviceId());
            activate(c);
            return dashboard(owner);
        });
    }
    private void activate(DeviceLicenseCode c) {
        DeviceLicenseGrant existing = grants.lockByDeviceId(c.getDeviceId()).orElse(null);
        if (existing != null && existing.getRevokedAt() == null) throw error("license_device_already_bound");
        if (capacity(c.getOwnerUserId()) <= bound(c.getOwnerUserId()).size()) throw error("license_no_slots");
        grants.saveAndFlush(DeviceLicenseGrant.builder().deviceId(c.getDeviceId()).ownerUserId(c.getOwnerUserId())
                .name(c.getDeviceName()).platform(c.getPlatform()).activatedAt(Instant.now()).legacy(false).build());
        c.setStatus("REDEEMED"); c.setRedeemedAt(Instant.now()); codes.saveAndFlush(c);
        audit(c.getOwnerUserId(),"AUTHORIZED",c.getDeviceId(),c.getId());
    }
    public void cancel(Long owner, String id) {
        tx(() -> { lockOwner(owner); DeviceLicenseCode c=ownedCode(owner,id);
            if (PENDING.contains(c.getStatus())) { c.setStatus("CANCELLED"); codes.save(c); audit(owner,"CANCELLED",c.getDeviceId(),c.getId()); } return null; });
    }
    private DeviceLicenseCode ownedCode(Long owner,String id) {
        DeviceLicenseCode c=codes.findById(id).orElseThrow(() -> error("license_request_missing"));
        if (!c.getOwnerUserId().equals(owner)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        return c;
    }
    public void revoke(Long owner,String deviceId) {
        guard.check("replace:"+owner,replacementsPerDay,86400000);
        tx(() -> { lockOwner(owner); credentials.lockByDeviceId(deviceId);
            DeviceLicenseGrant g=grants.lockByDeviceId(deviceId).orElseThrow(() -> error("license_device_missing"));
            if (!g.getOwnerUserId().equals(owner)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
            if (g.getRevokedAt()==null) { g.setRevokedAt(Instant.now()); grants.save(g); audit(owner,"REVOKED",deviceId,null); }
            return null; });
    }
    public void release(String deviceId) {
        DeviceLicenseGrant g=grants.findById(deviceId).orElseThrow(() -> error("license_device_missing"));
        revoke(g.getOwnerUserId(),deviceId);
    }
    public void rename(Long owner,String deviceId,String name) {
        tx(() -> { lockOwner(owner);
            DeviceLicenseGrant g=grants.lockByDeviceId(deviceId).orElseThrow(() -> error("license_device_missing"));
            if (!g.getOwnerUserId().equals(owner)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
            g.setName(clean(name,"Device",128)); grants.save(g); audit(owner,"RENAMED",deviceId,null); return null; });
    }
    public void revokeDeletedOwner(Long owner) {
        tx(() -> {
            lockOwner(owner);
            for (DeviceLicenseGrant g : bound(owner)) {
                g.setRevokedAt(Instant.now()); grants.save(g);
                audit(owner,"ACCOUNT_DELETED",g.getDeviceId(),null);
            }
            for (DeviceLicenseCode c : pending(owner)) { c.setStatus("CANCELLED"); codes.save(c); }
            return null;
        });
    }
    /** One-time import: later purchases never silently authorize signed-in devices. */
    public void migrateLegacy() {
        tx(() -> { migration.initialize(); return null; });
        tx(() -> {
            DeviceLicenseMigration marker=migration.lockSingleton();
            if (marker.isCompleted()) return null;
            // Preserve connections that existed before separating billing from pairing.
            Map<Long,List<Device>> legacyPeers = new HashMap<>();
            for (Device d : devices.findAll()) if (d.isActive())
                legacyPeers.computeIfAbsent(d.getUser().getId(), k -> new ArrayList<>()).add(d);
            for (List<Device> group : legacyPeers.values())
                for (int i=0; i<group.size(); i++) for (int j=i+1; j<group.size(); j++)
                    pairing.pair(group.get(i).getDeviceId(), group.get(j).getDeviceId());
            for (MembershipEntitlement e:entitlements.findAll()) {
                if ("FREE".equalsIgnoreCase(e.getTierCode())) continue;
                Long owner=e.getUser().getId(); lockOwner(owner);
                List<Device> old=devices.findAllByUser_IdAndActiveTrue(owner);
                accounts.save(DeviceLicenseAccount.builder().userId(owner).legacyExtraSlots(Math.max(0,old.size()-e.getDeviceLimit())).migratedAt(Instant.now()).build());
                for (Device d:old) {
                    // A device credential is created on the next device session if absent.
                    if (!grants.existsById(d.getDeviceId())) grants.save(DeviceLicenseGrant.builder()
                            .deviceId(d.getDeviceId()).ownerUserId(owner).name(clean(d.getName(),"Device",128))
                            .platform(clean(d.getPlatform(),"unknown",32)).activatedAt(Instant.now()).legacy(true).build());
                }
            }
            marker.setCompleted(true); migration.save(marker); return null;
        });
    }
    private static Map<String,Object> map(Object... pairs) {
        Map<String,Object> out=new LinkedHashMap<>();
        for(int i=0;i<pairs.length;i+=2) out.put((String)pairs[i],pairs[i+1]);
        return out;
    }
}
