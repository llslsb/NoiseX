package com.noisex.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.noisex.exception.ErrorCode;
import com.noisex.model.dto.ApiResponse;
import com.noisex.security.JwtAuthenticationFilter;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final ObjectMapper objectMapper;

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(
                        e ->
                                e.authenticationEntryPoint(
                                                (request, response, authException) -> {
                                                    response.setStatus(
                                                            HttpServletResponse.SC_UNAUTHORIZED);
                                                    response.setContentType(
                                                            MediaType.APPLICATION_JSON_VALUE);
                                                    response.setCharacterEncoding("UTF-8");
                                                    ApiResponse<Void> apiResponse =
                                                            ApiResponse.error(
                                                                    ErrorCode.UNAUTHORIZED
                                                                            .getCode(),
                                                                    ErrorCode.UNAUTHORIZED
                                                                            .getMessage());
                                                    response.getWriter()
                                                            .write(
                                                                    objectMapper.writeValueAsString(
                                                                            apiResponse));
                                                })
                                        .accessDeniedHandler(
                                                (request, response, accessDeniedException) -> {
                                                    response.setStatus(
                                                            HttpServletResponse.SC_FORBIDDEN);
                                                    response.setContentType(
                                                            MediaType.APPLICATION_JSON_VALUE);
                                                    response.setCharacterEncoding("UTF-8");
                                                    ApiResponse<Void> apiResponse =
                                                            ApiResponse.error(
                                                                    ErrorCode.FORBIDDEN.getCode(),
                                                                    ErrorCode.FORBIDDEN
                                                                            .getMessage());
                                                    response.getWriter()
                                                            .write(
                                                                    objectMapper.writeValueAsString(
                                                                            apiResponse));
                                                }))
                .authorizeHttpRequests(
                        auth ->
                                auth.requestMatchers("/api/auth/**")
                                        .permitAll()
                                        .requestMatchers("/api/time")
                                        .permitAll()
                                        .requestMatchers("/ws/**")
                                        .permitAll()
                                        .requestMatchers(
                                                "/swagger-ui/**",
                                                "/v3/api-docs/**",
                                                "/swagger-ui.html")
                                        .permitAll()
                                        .requestMatchers("/actuator/health/**")
                                        .permitAll()
                                        .requestMatchers("/actuator/prometheus")
                                        .permitAll()
                                        .requestMatchers("/actuator/metrics/**")
                                        .permitAll()
                                        .requestMatchers("/admin.html", "/static/**")
                                        .permitAll()
                                        .requestMatchers("/api/admin/**")
                                        .hasRole("ADMIN")
                                        .anyRequest()
                                        .authenticated())
                .addFilterBefore(
                        jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }
}
