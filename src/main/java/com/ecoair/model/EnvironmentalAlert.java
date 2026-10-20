package com.ecoair.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.Instant;

@Entity
@Table(name = "environmental_alerts")
public class EnvironmentalAlert {

    public enum Level { LOW, MEDIUM, HIGH, CRITICAL }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    private String stationId;

    @NotBlank
    private String metric;          // ej: PM2.5, CO2, temperatura

    @NotNull
    private Double value;

    @Enumerated(EnumType.STRING)
    private Level level;

    private Instant createdAt;

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
        if (level == null) level = Level.LOW;
    }

    public Long getId() { return id; }
    public String getStationId() { return stationId; }
    public void setStationId(String stationId) { this.stationId = stationId; }
    public String getMetric() { return metric; }
    public void setMetric(String metric) { this.metric = metric; }
    public Double getValue() { return value; }
    public void setValue(Double value) { this.value = value; }
    public Level getLevel() { return level; }
    public void setLevel(Level level) { this.level = level; }
    public Instant getCreatedAt() { return createdAt; }
}
