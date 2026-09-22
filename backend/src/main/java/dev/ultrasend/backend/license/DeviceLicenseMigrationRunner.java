package dev.ultrasend.backend.license;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
@Component @RequiredArgsConstructor
public class DeviceLicenseMigrationRunner implements ApplicationRunner {
    private final DeviceLicenseService licenses;
    @Override public void run(ApplicationArguments args) { licenses.migrateLegacy(); }
}
