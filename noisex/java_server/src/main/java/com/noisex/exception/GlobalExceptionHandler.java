package com.noisex.exception;

import com.noisex.model.dto.ApiResponse;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.security.SignatureException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusinessException(BusinessException e) {
        log.warn("Business error: code={}, message={}", e.getCode(), e.getMessage());
        HttpStatus status = mapCodeToStatus(e.getCode());
        return ResponseEntity.status(status).body(ApiResponse.error(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(RateLimitException.class)
    public ResponseEntity<ApiResponse<Void>> handleRateLimitException(RateLimitException e) {
        log.warn("Rate limit: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(ApiResponse.error(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleNotFoundException(NotFoundException e) {
        log.warn("Not found: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidationException(
            MethodArgumentNotValidException e) {
        String message =
                e.getBindingResult().getFieldErrors().stream()
                        .map(error -> error.getField() + ": " + error.getDefaultMessage())
                        .findFirst()
                        .orElse("参数验证失败");
        log.warn("Validation error: {}", message);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(ErrorCode.BAD_REQUEST.getCode(), message));
    }

    @ExceptionHandler(ExpiredJwtException.class)
    public ResponseEntity<ApiResponse<Void>> handleExpiredJwt(ExpiredJwtException e) {
        log.warn("JWT expired: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(
                        ApiResponse.error(
                                ErrorCode.TOKEN_EXPIRED.getCode(),
                                ErrorCode.TOKEN_EXPIRED.getMessage()));
    }

    @ExceptionHandler(SignatureException.class)
    public ResponseEntity<ApiResponse<Void>> handleInvalidJwt(SignatureException e) {
        log.warn("JWT signature invalid: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(
                        ApiResponse.error(
                                ErrorCode.UNAUTHORIZED.getCode(),
                                ErrorCode.UNAUTHORIZED.getMessage()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiResponse<Void>> handleIllegalArgument(IllegalArgumentException e) {
        log.warn("Illegal argument: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(ErrorCode.BAD_REQUEST.getCode(), e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleGenericException(Exception e) {
        log.error("Unexpected error", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(
                        ApiResponse.error(
                                ErrorCode.INTERNAL_ERROR.getCode(),
                                ErrorCode.INTERNAL_ERROR.getMessage()));
    }

    private HttpStatus mapCodeToStatus(int code) {
        if (code == ErrorCode.UNAUTHORIZED.getCode() || code == ErrorCode.TOKEN_EXPIRED.getCode()) {
            return HttpStatus.UNAUTHORIZED;
        }
        if (code == ErrorCode.FORBIDDEN.getCode()) {
            return HttpStatus.FORBIDDEN;
        }
        if (code == ErrorCode.RATE_LIMIT.getCode()) {
            return HttpStatus.TOO_MANY_REQUESTS;
        }
        if (code == ErrorCode.NOT_FOUND.getCode() || code == ErrorCode.SONAR_EXPIRED.getCode()) {
            return HttpStatus.NOT_FOUND;
        }
        if (code == ErrorCode.BAD_REQUEST.getCode()) {
            return HttpStatus.BAD_REQUEST;
        }
        if (code == ErrorCode.ROOM_CLOSED.getCode()) {
            return HttpStatus.CONFLICT;
        }
        return HttpStatus.INTERNAL_SERVER_ERROR;
    }
}
