package dev.ultrasend.backend.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/** /admin and /admin/ are not matched by the static welcome-page mechanism — redirect them. */
@Controller
public class AdminPageRedirectController {

    @GetMapping({"/admin", "/admin/"})
    public String admin() {
        return "redirect:/admin/index.html";
    }
}
