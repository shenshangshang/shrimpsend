package dev.ultrasend.backend.realtime;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
public class WukongimConfig {

    @Value("${wukongim.api-url:http://127.0.0.1:5001}")
    private String apiUrl;

    @Value("${wukongim.manager-token:}")
    private String managerToken;

    @Bean
    public WebClient wukongimWebClient() {
        WebClient.Builder builder = WebClient.builder()
                .baseUrl(apiUrl)
                .defaultHeader("Content-Type", "application/json");
        if (managerToken != null && !managerToken.isBlank()) {
            builder.defaultHeader("token", managerToken.trim());
        }
        return builder.build();
    }
}
