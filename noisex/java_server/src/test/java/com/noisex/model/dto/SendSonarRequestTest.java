package com.noisex.model.dto;

import static org.junit.jupiter.api.Assertions.*;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class SendSonarRequestTest {

    private Validator validator;

    @BeforeEach
    void setUp() {
        validator = Validation.buildDefaultValidatorFactory().getValidator();
    }

    @Test
    void validRequest_shouldHaveNoViolations() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello world");
        request.setGeohash("wx4g0s");

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertTrue(violations.isEmpty());
    }

    @Test
    void blankContent_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("");
        request.setGeohash("wx4g0s");

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void contentTooLong_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("x".repeat(141));
        request.setGeohash("wx4g0s");

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void geohashWrongLength_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello");
        request.setGeohash("wx4g"); // 长度 4，要求 6

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void geohashInvalidChars_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello");
        request.setGeohash("wx4i0s"); // 'i' 不是合法 base32 字符

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void geohashWithLetterO_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello");
        request.setGeohash("wx4o0s"); // 'o' 不是合法 base32 字符

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void geohashWithLetterL_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello");
        request.setGeohash("wx4l0s"); // 'l' 不是合法 base32 字符

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }

    @Test
    void geohashWithLetterA_shouldHaveViolation() {
        SendSonarRequest request = new SendSonarRequest();
        request.setContent("Hello");
        request.setGeohash("wx4a0s"); // 'a' 不是合法 base32 字符

        Set<ConstraintViolation<SendSonarRequest>> violations = validator.validate(request);
        assertFalse(violations.isEmpty());
    }
}
