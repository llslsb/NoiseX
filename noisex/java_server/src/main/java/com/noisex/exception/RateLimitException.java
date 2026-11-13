package com.noisex.exception;

public class RateLimitException extends BusinessException {
    public RateLimitException(String message) {
        super(ErrorCode.RATE_LIMIT, message);
    }
}
