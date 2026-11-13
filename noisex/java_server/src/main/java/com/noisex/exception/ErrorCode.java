package com.noisex.exception;

public enum ErrorCode {
    SUCCESS(0, "成功"),
    BAD_REQUEST(40001, "参数错误"),
    UNAUTHORIZED(40101, "未认证"),
    TOKEN_EXPIRED(40102, "Token 过期"),
    RATE_LIMIT(40301, "频率限制"),
    FORBIDDEN(40302, "无权限"),
    NOT_FOUND(40401, "资源不存在"),
    SONAR_EXPIRED(40901, "声呐已过期"),
    ROOM_CLOSED(40902, "房间已关闭"),
    INTERNAL_ERROR(50001, "服务内部错误");

    private final int code;
    private final String message;

    ErrorCode(int code, String message) {
        this.code = code;
        this.message = message;
    }

    public int getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }
}
