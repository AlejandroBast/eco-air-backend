package com.ecoair.repository;

import com.ecoair.model.EnvironmentalAlert;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EnvironmentalAlertRepository extends JpaRepository<EnvironmentalAlert, Long> {
    List<EnvironmentalAlert> findByLevel(EnvironmentalAlert.Level level);
}
