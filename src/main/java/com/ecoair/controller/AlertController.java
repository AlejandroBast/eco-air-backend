package com.ecoair.controller;

import com.ecoair.model.EnvironmentalAlert;
import com.ecoair.repository.EnvironmentalAlertRepository;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class AlertController {

    private final EnvironmentalAlertRepository repository;

    @Value("${OPERATOR_ID:unknown}")
    private String operatorId;

    public AlertController(EnvironmentalAlertRepository repository) {
        this.repository = repository;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP", "operator", operatorId);
    }

    @GetMapping("/alerts")
    public List<EnvironmentalAlert> all() {
        return repository.findAll();
    }

    @GetMapping("/alerts/critical")
    public List<EnvironmentalAlert> critical() {
        return repository.findByLevel(EnvironmentalAlert.Level.CRITICAL);
    }

    @PostMapping("/alerts")
    @ResponseStatus(HttpStatus.CREATED)
    public EnvironmentalAlert create(@Valid @RequestBody EnvironmentalAlert alert) {
        return repository.save(alert);
    }
}
