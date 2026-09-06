package dev.ultrasend.backend.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import java.util.Properties;

import jakarta.mail.internet.MimeMessage;

/**
 * Generic SMTP mail sender whose credentials come from the runtime
 * {@code app_settings} table (admin UI) with environment fallbacks, so a
 * self-hosted deployment can use any mailbox (QQ/163/Gmail/own relay) without
 * SendCloud and without a restart.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SmtpMailService {

    private static final String ENV_HOST = System.getenv("SPRING_MAIL_HOST");
    private static final String ENV_PORT = System.getenv("SPRING_MAIL_PORT");
    private static final String ENV_USER = System.getenv("SPRING_MAIL_USERNAME");
    private static final String ENV_PASS = System.getenv("SPRING_MAIL_PASSWORD");

    public static final String ENV_FROM = System.getenv("MAIL_FROM");
    public static final String ENV_FROM_NAME = System.getenv("MAIL_FROM_NAME");

    private final AppSettingsService settings;

    public boolean isConfigured() {
        return host() != null && !host().isBlank()
                && user() != null && !user().isBlank()
                && pass() != null && !pass().isBlank();
    }

    private String host() {
        return settings.get("smtp.host", ENV_HOST);
    }

    private int port() {
        String raw = settings.get("smtp.port", ENV_PORT);
        try {
            return raw == null || raw.isBlank() ? 587 : Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            return 587;
        }
    }

    private String user() {
        return settings.get("smtp.username", ENV_USER);
    }

    private String pass() {
        return settings.get("smtp.password", ENV_PASS);
    }

    private String from() {
        String v = settings.get("smtp.from", ENV_FROM);
        return v == null || v.isBlank() ? user() : v;
    }

    private String fromName() {
        return settings.get("smtp.from-name", ENV_FROM_NAME == null ? "虾传" : ENV_FROM_NAME);
    }

    private boolean starttls() {
        return settings.getBool("smtp.starttls", true);
    }

    private boolean ssl() {
        return settings.getBool("smtp.ssl", false);
    }

    public void sendVerificationCode(String to, String code) {
        sendHtml(to, "虾传 邮箱验证码", buildVerificationHtml(code));
    }

    public void sendHtml(String to, String subject, String html) {
        JavaMailSenderImpl sender = new JavaMailSenderImpl();
        sender.setHost(host());
        sender.setPort(port());
        sender.setUsername(user());
        sender.setPassword(pass());
        sender.setDefaultEncoding("UTF-8");
        Properties props = sender.getJavaMailProperties();
        props.put("mail.smtp.auth", "true");
        props.put("mail.smtp.starttls.enable", Boolean.toString(starttls()));
        props.put("mail.smtp.ssl.enable", Boolean.toString(ssl()));
        props.put("mail.smtp.connectiontimeout", "10000");
        props.put("mail.smtp.timeout", "15000");
        props.put("mail.smtp.writetimeout", "15000");

        try {
            MimeMessage message = sender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, false, "UTF-8");
            helper.setFrom(from(), fromName());
            helper.setTo(to);
            helper.setSubject(subject);
            helper.setText(html, true);
            sender.send(message);
            log.info("smtp mail sent to={} subject={}", to, subject);
        } catch (Exception e) {
            log.error("smtp mail send failed to={}", to, e);
            throw new RuntimeException("SMTP 邮件发送失败: " + e.getMessage());
        }
    }

    private String buildVerificationHtml(String code) {
        return """
                <div style="max-width:400px;margin:40px auto;font-family:system-ui,-apple-system,sans-serif;background:#f9fafb;border-radius:12px;padding:32px;text-align:center">
                  <h2 style="margin:0 0 8px">虾传 邮箱验证码</h2>
                  <p style="color:#6b7280;font-size:14px;margin:0 0 20px">验证码 10 分钟内有效，请勿泄露给他人</p>
                  <div style="font-size:36px;letter-spacing:10px;font-weight:700;color:#111827">%s</div>
                </div>
                """.formatted(code);
    }
}
