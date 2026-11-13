package com.noisex.config;

import com.noisex.websocket.NoiseXWebSocketHandler;
import com.noisex.websocket.WebSocketInterceptor;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketConfigurer {

    private final NoiseXWebSocketHandler webSocketHandler;
    private final WebSocketInterceptor webSocketInterceptor;

    @Value("${noisex.websocket.allowed-origins}")
    private String[] allowedOrigins;

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(webSocketHandler, "/ws")
                .addInterceptors(webSocketInterceptor)
                .setAllowedOrigins(allowedOrigins);
    }
}
