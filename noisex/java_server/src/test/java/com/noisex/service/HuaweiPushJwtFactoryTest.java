package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** 鸿蒙 Push v3 服务账号密钥 JWT 工厂单测：PS256 签名 / kid / iss / aud / iat / exp 缺一不可 */
class HuaweiPushJwtFactoryTest {

    /** PKCS#8 私钥字节转 PEM 文本（模拟 AGC 下载的真实密钥文件格式） */
    private static String pemOf(byte[] pkcs8Der) {
        String base64 = Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(pkcs8Der);
        return "-----BEGIN PRIVATE KEY-----\n" + base64 + "\n-----END PRIVATE KEY-----";
    }

    private static KeyPair generateRsaKeyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        return generator.generateKeyPair();
    }

    private static String keyFileJson(String pem) throws Exception {
        Map<String, Object> keyFile =
                Map.of(
                        "project_id",
                        "101653523864146031",
                        "key_id",
                        "kid-test-1",
                        "private_key",
                        pem,
                        "sub_account",
                        "sub-acc-test-1",
                        "token_uri",
                        "https://oauth-login.cloud.huawei.com/oauth2/v3/token");
        return new ObjectMapper().writeValueAsString(keyFile);
    }

    @Test
    void buildJwt_shouldSignPs256WithKidAndOfficialClaims() throws Exception {
        KeyPair pair = generateRsaKeyPair();
        String json = keyFileJson(pemOf(pair.getPrivate().getEncoded()));

        HuaweiPushJwtFactory.ServiceAccountKey key = HuaweiPushJwtFactory.parse(json);
        Instant now = Instant.now();
        String jwt = HuaweiPushJwtFactory.buildJwt(key, now);

        var parsed = Jwts.parser().verifyWith(pair.getPublic()).build().parseSignedClaims(jwt);
        assertEquals("PS256", parsed.getHeader().getAlgorithm());
        assertEquals("kid-test-1", parsed.getHeader().get("kid"));

        Claims claims = parsed.getPayload();
        assertEquals("sub-acc-test-1", claims.getIssuer());
        assertTrue(
                claims.getAudience()
                        .contains("https://oauth-login.cloud.huawei.com/oauth2/v3/token"));
        assertEquals(now.getEpochSecond(), claims.getIssuedAt().getTime() / 1000);
        assertEquals(
                now.plusSeconds(HuaweiPushJwtFactory.JWT_TTL_SECONDS).getEpochSecond(),
                claims.getExpiration().getTime() / 1000);
    }

    @Test
    void parse_shouldRejectKeyFileWithoutPrivateKey() {
        assertThrows(
                Exception.class,
                () ->
                        HuaweiPushJwtFactory.parse(
                                new ObjectMapper()
                                        .writeValueAsString(
                                                Map.of(
                                                        "project_id",
                                                        "p",
                                                        "key_id",
                                                        "k",
                                                        "sub_account",
                                                        "s"))));
    }

    /** 防御性断言：TTL 必须正好是官方上限 3600 秒，改短会频繁失效，改长会被华为拒 */
    @Test
    void jwtTtl_shouldBeExactly3600Seconds() {
        assertEquals(3600, HuaweiPushJwtFactory.JWT_TTL_SECONDS);
    }
}
