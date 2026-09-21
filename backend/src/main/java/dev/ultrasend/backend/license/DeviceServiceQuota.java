package dev.ultrasend.backend.license;

import dev.ultrasend.backend.service.DeviceSendRateLimit;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.LinkedHashMap;
import java.util.Map;

/** Shared SQL counters. Only signaling metadata visits this path, never file bytes. */
@Service @RequiredArgsConstructor
public class DeviceServiceQuota {
    private final DeviceLicenseService licenses;
    private final LicenseRateBucketRepository buckets;
    private final LicenseCodeCodec codec;
    private final PlatformTransactionManager transactions;
    private static final long SESSION_MS = 15 * 60_000L;
    private static final int SESSION_MESSAGES = 256;

    public boolean acquire(String device, Object envelope) {
        String type = DeviceSendRateLimit.envelopeType(envelope);
        boolean authorized = licenses.isAuthorized(device);
        String session = sessionKey(device, type, envelope);
        return Boolean.TRUE.equals(new TransactionTemplate(transactions).execute(status -> {
            if (!take(locked("safety:"+device, 60_000), 6000)) return false;
            if (authorized) return true;
            // Always lock the commercial bucket before a session bucket (consistent lock order).
            LicenseRateBucket commercial = locked(DeviceSendRateLimit.bucketKey(device,type),60_000);
            if (session != null) {
                LicenseRateBucket ongoing = locked(session, SESSION_MS);
                // Once admitted, a bounded negotiation/cancel/recovery budget survives exhaustion
                // of the new-session quota. Each endpoint is admitted against its own allowance.
                if (ongoing.getHits() > 0) return take(ongoing, SESSION_MESSAGES);
                if (!take(commercial, DeviceSendRateLimit.maxPerWindow(type))) return false;
                return take(ongoing, SESSION_MESSAGES);
            }
            return take(commercial, DeviceSendRateLimit.maxPerWindow(type));
        }));
    }
    private String sessionKey(String device, String type, Object envelope) {
        if (type == null || !type.startsWith("webrtc_") || !(envelope instanceof Map<?,?> e)
                || !(e.get("payload") instanceof Map<?,?> p)) return null;
        Object s = p.get("sessionId");
        Object peer = e.get("toDeviceId") != null ? e.get("toDeviceId") : p.get("targetDeviceId");
        if (!(s instanceof String sid) || sid.isBlank() || sid.length()>128 || !(peer instanceof String id) || id.isBlank()) return null;
        return "signal-session:"+device+":"+id+":"+sid;
    }
    private LicenseRateBucket locked(String key,long window) {
        long now=System.currentTimeMillis();
        String id=codec.hash("quota",key);
        buckets.initialize(id,now);
        LicenseRateBucket row=buckets.lock(id);
        if(now>=row.getWindowStartedAt()+window) { row.setWindowStartedAt(now); row.setHits(0); }
        return row;
    }
    private boolean take(LicenseRateBucket row,int max) {
        if(row.getHits()>=max) return false;
        row.setHits(row.getHits()+1); buckets.save(row); return true;
    }
    private Map<String,Object> snapshot(String device,String type) {
        int limit=DeviceSendRateLimit.maxPerWindow(type);
        LicenseRateBucket row=buckets.findById(codec.hash("quota",DeviceSendRateLimit.bucketKey(device,type))).orElse(null);
        long remaining=row==null?0:Math.max(0,row.getWindowStartedAt()+60_000-System.currentTimeMillis());
        int used=remaining==0?0:row.getHits();
        return Map.of("used",used,"limit",limit,"remaining",Math.max(0,limit-used),"retryAfterMs",used>=limit?remaining:0);
    }
    public Map<String,Object> view(String device) {
        boolean unlimited=licenses.isAuthorized(device);
        Map<String,Object> result=new LinkedHashMap<>();
        Map<String,Object> unlimitedBucket=Map.of("used",0,"limit",Integer.MAX_VALUE,"remaining",Integer.MAX_VALUE,"retryAfterMs",0);
        result.put("message",unlimited?unlimitedBucket:snapshot(device,"text"));
        result.put("signaling",unlimited?unlimitedBucket:snapshot(device,"webrtc_offer"));
        result.put("unlimited",unlimited);
        return result;
    }
}
