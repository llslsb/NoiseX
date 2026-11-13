package com.noisex.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class MetricsConfig {

    @Bean
    public Counter sonarSentCounter(MeterRegistry registry) {
        return Counter.builder("noisex.sonar.sent.total")
                .description("Total number of sonars sent")
                .register(registry);
    }

    @Bean
    public Counter sonarAcceptedCounter(MeterRegistry registry) {
        return Counter.builder("noisex.sonar.accepted.total")
                .description("Total number of sonars accepted")
                .register(registry);
    }

    @Bean
    public Counter roomCreatedCounter(MeterRegistry registry) {
        return Counter.builder("noisex.room.created.total")
                .description("Total number of chat rooms created")
                .register(registry);
    }

    @Bean
    public Counter messageSentCounter(MeterRegistry registry) {
        return Counter.builder("noisex.chat.message.sent.total")
                .description("Total number of chat messages sent")
                .register(registry);
    }
}
