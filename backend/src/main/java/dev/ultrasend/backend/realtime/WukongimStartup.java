package dev.ultrasend.backend.realtime;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@ConditionalOnProperty(name = "realtime.bus", havingValue = "wukongim", matchIfMissing = true)
@RequiredArgsConstructor
@Slf4j
public class WukongimStartup implements ApplicationRunner {

    private final WukongimApiClient wukongimApiClient;

    @Value("${wukongim.system-uid:ultrasend}")
    private String systemUid;

    @Override
    public void run(ApplicationArguments args) {
        try {
            wukongimApiClient.addSystemUids(List.of(systemUid));
            log.info("wukongim system uid registered uid={}", systemUid);
        } catch (Exception e) {
            log.warn("wukongim system uid register skipped: {}", e.getMessage());
        }
    }
}
