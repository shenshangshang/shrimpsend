package dev.ultrasend.backend.license;

import dev.ultrasend.backend.entity.*;
import dev.ultrasend.backend.repository.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.mock.mockito.SpyBean;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@DataJpaTest(properties={"spring.datasource.url=jdbc:h2:mem:licenses;MODE=MySQL;DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000",
        "spring.datasource.driver-class-name=org.h2.Driver", "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "app.device-license.secret=local-test-license-secret-at-least-32-characters", "app.device-license.namespace=T"})
@AutoConfigureTestDatabase(replace=AutoConfigureTestDatabase.Replace.NONE)
@Import({dev.ultrasend.backend.service.DevicePairingService.class,DeviceLicenseService.class,LicenseCodeCodec.class,LicenseAbuseGuard.class,DeviceServiceQuota.class})
@Transactional(propagation=Propagation.NOT_SUPPORTED)
class DeviceLicenseServiceTest {
    @Autowired DeviceLicenseService service;
    @Autowired DeviceServiceQuota quota;
    @Autowired LicenseRateBucketRepository buckets;
    @Autowired DeviceLicenseAuditRepository audit;
    @Autowired DeviceRepository legacyDevices;
    @Autowired dev.ultrasend.backend.service.DevicePairingService pairing;
    @Autowired UserRepository users;
    @Autowired MembershipEntitlementRepository entitlements;
    @Autowired DeviceCredentialRepository credentials;
    @Autowired DeviceLicenseCodeRepository codes;
    @Autowired DeviceLicenseGrantRepository grants;
    @org.springframework.boot.test.mock.mockito.MockBean dev.ultrasend.backend.service.DeviceIdentityService identity;
    @SpyBean LicenseCodeCodec codec;
    Long owner;
    String deviceA, deviceB;
    @BeforeEach void setup() {
        owner=createOwner(2);
        deviceA=device(); deviceB=device();
    }
    @AfterEach void resetCodec() { doCallRealMethod().when(codec).newCode(); }
    Long createOwner(int slots) {
        User u=users.saveAndFlush(User.builder().email(UUID.randomUUID()+"@local.invalid").passwordHash("test").build());
        entitlements.saveAndFlush(MembershipEntitlement.builder().user(u).tierCode("PRO").deviceLimit(slots).addonPacks(0)
                .isLifetime(true).effectiveAt(Instant.now()).updatedAt(Instant.now()).build());
        return u.getId();
    }
    String device() {
        String id="license-test-"+UUID.randomUUID();
        credentials.saveAndFlush(DeviceCredential.builder().deviceId(id).secretHash("test").createdAt(Instant.now()).lastIssuedAt(Instant.now()).build());
        return id;
    }
    Map<String,Object> redeem(Map<String,Object> c,String device,boolean qr) {
        return service.redeem(device, qr ? null:(String)c.get("code"), qr ? (String)c.get("qrToken"):null,"Test Mac","macos",device);
    }
    @Test void manualCodeRequiresOwnerApprovalAndDoesNotSignInDevice() {
        Map<String,Object> code=service.issue(owner);
        assertTrue(((String)code.get("code")).matches("[A-HJ-NP-Z2-9]{6}"));
        assertEquals(false,redeem(code,deviceA,false).get("authorized"));
        assertFalse(service.isAuthorized(deviceA));
        assertThrows(ResponseStatusException.class,()->service.approve(createOwner(1),(String)code.get("id")));
        service.approve(owner,(String)code.get("id"));
        assertTrue(service.isAuthorized(deviceA));
        assertEquals(1,service.authorizedCount(owner));
        assertEquals(true,redeem(code,deviceA,false).get("authorized"));
        assertFalse(service.isAuthorized(deviceB));
    }
    @Test void qrAndCodeCanOnlyConsumeOneDeviceAndRetryIsIdempotent() {
        Map<String,Object> code=service.issue(owner);
        redeem(code,deviceA,true);
        redeem(code,deviceA,true);
        assertEquals(1,service.authorizedCount(owner));
        assertThrows(ResponseStatusException.class,()->redeem(code,deviceB,false));
    }
    @Test void lastSlotIsReservedAndCancelReleasesIt() {
        Long one=createOwner(1);
        Map<String,Object> code=service.issue(one);
        assertThrows(ResponseStatusException.class,()->service.issue(one));
        service.cancel(one,(String)code.get("id"));
        assertThrows(ResponseStatusException.class,()->redeem(code,deviceA,true));
        assertNotNull(service.issue(one));
    }
    @Test void expiryAndRefundPreventActivation() {
        Map<String,Object> code=service.issue(owner);
        DeviceLicenseCode row=codes.findById((String)code.get("id")).orElseThrow();
        row.setExpiresAt(Instant.now().minusSeconds(1)); codes.saveAndFlush(row);
        assertThrows(ResponseStatusException.class,()->redeem(code,deviceA,true));
        Map<String,Object> fresh=service.issue(owner);
        MembershipEntitlement e=entitlements.findByUserId(owner).orElseThrow();
        e.setTierCode("FREE"); entitlements.saveAndFlush(e);
        assertThrows(ResponseStatusException.class,()->redeem(fresh,deviceA,true));
    }
    @Test void revokeAllowsReplacementButOldCodeCannotReactivate() {
        Map<String,Object> old=service.issue(owner); redeem(old,deviceA,true);
        service.revoke(owner,deviceA);
        assertFalse(service.isAuthorized(deviceA));
        assertEquals(false,redeem(old,deviceA,true).get("authorized"));
        redeem(service.issue(owner),deviceB,true);
        assertTrue(service.isAuthorized(deviceB));
    }
    @Test void anotherOwnerCannotOverwriteAnExistingGrant() {
        redeem(service.issue(owner),deviceA,true);
        Map<String,Object> other=service.issue(createOwner(1));
        assertThrows(ResponseStatusException.class,()->redeem(other,deviceA,true));
        assertEquals(owner,grants.findById(deviceA).orElseThrow().getOwnerUserId());
    }
    @Test void renewRestoresExistingDeviceWithoutAnotherCode() {
        redeem(service.issue(owner),deviceA,true);
        MembershipEntitlement e=entitlements.findByUserId(owner).orElseThrow();
        e.setIsLifetime(false); e.setSubscriptionExpiresAt(Instant.now().minusSeconds(1)); entitlements.saveAndFlush(e);
        assertFalse(service.isAuthorized(deviceA));
        e.setSubscriptionExpiresAt(Instant.now().plusSeconds(3600)); entitlements.saveAndFlush(e);
        assertTrue(service.isAuthorized(deviceA));
    }
    @Test void databaseUniquenessRetriesCodeCollisionsWithoutLeakingReservations() {
        doReturn("TAAAAA","TAAAAA","TBBBBB").when(codec).newCode();
        Map<String,Object> first=service.issue(owner), second=service.issue(owner);
        assertNotEquals(first.get("code"),second.get("code"));
        assertEquals(2,service.dashboard(owner).get("reserved"));
    }
    @Test void concurrentLastSlotIssueHasOneWinner() throws Exception {
        Long one=createOwner(1);
        assertEquals(1,concurrent(() -> service.issue(one),() -> service.issue(one)));
        assertEquals(1,service.dashboard(one).get("reserved"));
    }
    @Test void concurrentCodeRedemptionHasOneWinner() throws Exception {
        Map<String,Object> code=service.issue(owner);
        assertEquals(1,concurrent(() -> redeem(code,deviceA,true),() -> redeem(code,deviceB,true)));
        assertEquals(1,service.authorizedCount(owner));
    }
    @Test void concurrentDifferentOwnersCannotBothAuthorizeOneDevice() throws Exception {
        Map<String,Object> first=service.issue(owner), second=service.issue(createOwner(1));
        assertEquals(1,concurrent(() -> redeem(first,deviceA,true),() -> redeem(second,deviceA,true)));
    }
    @Test void billingOwnerDoesNotCreateTransferPairing() {
        redeem(service.issue(owner),deviceA,true); redeem(service.issue(owner),deviceB,true);
        assertFalse(pairing.canSignal(deviceA,deviceB));
        pairing.pair(deviceA,deviceB); assertTrue(pairing.canSignal(deviceA,deviceB));
        pairing.unpair(deviceA,deviceB); assertFalse(pairing.canSignal(deviceA,deviceB));
        assertTrue(service.isAuthorized(deviceB));
    }
    @Test void freeQuotaIsSharedAndExistingNegotiationSurvivesNewSessionExhaustion() {
        Map<String,Object> offer=Map.of("type","webrtc_offer","toDeviceId",deviceB,"payload",Map.of("sessionId","one"));
        assertTrue(quota.acquire(deviceA,offer));
        buckets.saveAndFlush(LicenseRateBucket.builder().id(codec.hash("quota","device-send-sig:"+deviceA))
                .windowStartedAt(System.currentTimeMillis()).hits(600).build());
        assertFalse(quota.acquire(deviceA,Map.of("type","webrtc_offer","toDeviceId",deviceB,"payload",Map.of("sessionId","two"))));
        assertTrue(quota.acquire(deviceA,Map.of("type","webrtc_ice_candidate","toDeviceId",deviceB,"payload",Map.of("sessionId","one"))));
        assertTrue(quota.acquire(deviceA,Map.of("type","webrtc_transfer_cancel","toDeviceId",deviceB,"payload",Map.of("sessionId","one"))));
        assertTrue(quota.acquire(deviceA,Map.of("type","text")));
    }
    @Test void licenseBypassesCommercialQuotaButRevokeAndSafetyApplyImmediately() {
        buckets.saveAndFlush(LicenseRateBucket.builder().id(codec.hash("quota","device-send-msg:"+deviceA))
                .windowStartedAt(System.currentTimeMillis()).hits(90).build());
        assertFalse(quota.acquire(deviceA,Map.of("type","text")));
        redeem(service.issue(owner),deviceA,true);
        assertTrue(quota.acquire(deviceA,Map.of("type","text")));
        assertEquals(true,quota.view(deviceA).get("unlimited"));
        buckets.saveAndFlush(LicenseRateBucket.builder().id(codec.hash("quota","safety:"+deviceA))
                .windowStartedAt(System.currentTimeMillis()).hits(6000).build());
        assertFalse(quota.acquire(deviceA,Map.of("type","text")));
        buckets.deleteById(codec.hash("quota","safety:"+deviceA));
        service.revoke(owner,deviceA);
        assertFalse(quota.acquire(deviceA,Map.of("type","text")));
        assertEquals(false,quota.view(deviceA).get("unlimited"));
    }
    @Test void downgradeKeepsOldestDevicesAndRenewalRestoresOthers() {
        redeem(service.issue(owner),deviceA,true); redeem(service.issue(owner),deviceB,true);
        MembershipEntitlement e=entitlements.findByUserId(owner).orElseThrow();
        e.setDeviceLimit(1); entitlements.saveAndFlush(e);
        assertTrue(service.isAuthorized(deviceA)); assertFalse(service.isAuthorized(deviceB));
        e.setDeviceLimit(2); entitlements.saveAndFlush(e);
        assertTrue(service.isAuthorized(deviceB));
    }
    @Test void legacyMigrationPreservesWebAllowancesOnlyOnce() {
        Long legacy=createOwner(1);
        for(String id:List.of(deviceA,deviceB)) legacyDevices.saveAndFlush(Device.builder().user(users.findById(legacy).orElseThrow())
                .deviceId(id).name("Old browser").platform("web").build());
        service.migrateLegacy();
        assertEquals(2,service.deviceCapacity(legacy));
        assertTrue(service.isAuthorized(deviceA)); assertTrue(service.isAuthorized(deviceB));
        assertTrue(pairing.canSignal(deviceA,deviceB));
        String later=device();
        legacyDevices.saveAndFlush(Device.builder().user(users.findById(legacy).orElseThrow()).deviceId(later).name("New login").platform("web").build());
        service.migrateLegacy();
        assertFalse(service.isAuthorized(later)); assertFalse(pairing.canSignal(deviceA,later));
        // A legacy device need not have a credential to be released from the purchaser UI.
        credentials.delete(credentials.findByDeviceId(deviceA).orElseThrow());
        service.revoke(legacy,deviceA); assertFalse(service.isAuthorized(deviceA));
    }
    @Test void auditTracksLifecycleWithoutSecrets() {
        Map<String,Object> code=service.issue(owner); redeem(code,deviceA,false);
        service.approve(owner,(String)code.get("id")); service.rename(owner,deviceA,"Laptop"); service.revoke(owner,deviceA);
        List<String> actions=audit.findAll().stream().filter(a -> a.getOwnerUserId().equals(owner)).map(DeviceLicenseAudit::getAction).toList();
        assertTrue(actions.containsAll(List.of("ISSUED","CLAIMED","AUTHORIZED","RENAMED","REVOKED")));
    }
    private int concurrent(Callable<?> first,Callable<?> second) throws Exception {
        ExecutorService pool=Executors.newFixedThreadPool(2);
        CountDownLatch start=new CountDownLatch(1);
        try {
            List<Future<Boolean>> runs=new ArrayList<>();
            for(Callable<?> job:List.of(first,second)) runs.add(pool.submit(() -> {
                start.await(); try { job.call(); return true; } catch(ResponseStatusException expected) { return false; }
            }));
            start.countDown(); int success=0;
            for(Future<Boolean> r:runs) if(r.get(20,TimeUnit.SECONDS)) success++;
            return success;
        } finally { pool.shutdownNow(); }
    }
}
