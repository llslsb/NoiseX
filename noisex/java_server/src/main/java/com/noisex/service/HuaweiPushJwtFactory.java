package com.noisex.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;

/**
 * 华为 Push v3 服务端鉴权工厂：基于「服务账号密钥」JSON 文件自签 JWT（PS256）。
 *
 * <p>2026-11-05 实锤（80200001 双平台验证）：鸿蒙与安卓的 Push REST API 已统一为 v3 接口 + 服务账号密钥自签
 * JWT——client_id/client_secret 的 OAuth client_credentials 拿到的 token 在两个平台都会被 80200001 拒收（v2 旧接口同样
 * 不认），旧 v2 通道整体作废。每个项目（鸿蒙项目/安卓项目各一）有自己的密钥 JSON（AGC API Console 下载），字段含 project_id / key_id /
 * private_key(PEM) / sub_account / token_uri；华为不存储私钥，文件只放服务器（600），严禁入库或进日志。
 *
 * <p>JWT 规则（官方 push-jwt-token 指南）：header kid=key_id、typ=JWT、alg=PS256 （SHA256withRSA/PSS）；payload
 * iss=sub_account、aud=token_uri、iat=签发时刻、 exp=iat+3600（上限 1 小时）。推送频率低，按每次调用现签现用，不做缓存。
 */
public final class HuaweiPushJwtFactory {

    /** 服务账号密钥文件的解析结果（不可变） */
    public record ServiceAccountKey(
            String projectId,
            String keyId,
            PrivateKey privateKey,
            String subAccount,
            String tokenUri) {}

    /** JWT 有效期：官方上限 3600 秒 */
    static final long JWT_TTL_SECONDS = 3600;

    private HuaweiPushJwtFactory() {}

    /** 解析服务账号密钥 JSON 文件内容为可签名对象 */
    public static ServiceAccountKey parse(String jsonContent) throws Exception {
        JsonNode node = new ObjectMapper().readTree(jsonContent);
        String pem = node.path("private_key").asText();
        if (pem.isBlank()) {
            throw new IllegalArgumentException("服务账号密钥缺少 private_key 字段");
        }
        String base64 =
                pem.replace("-----BEGIN PRIVATE KEY-----", "")
                        .replace("-----END PRIVATE KEY-----", "")
                        .replaceAll("\\s", "");
        byte[] der = Base64.getDecoder().decode(base64);
        PrivateKey privateKey =
                KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(der));
        return new ServiceAccountKey(
                node.path("project_id").asText(),
                node.path("key_id").asText(),
                privateKey,
                node.path("sub_account").asText(),
                node.path("token_uri")
                        .asText("https://oauth-login.cloud.huawei.com/oauth2/v3/token"));
    }

    /** 按官方规则自签推送 JWT：header 带 kid，PS256（SHA256withRSA/PSS）签名 */
    public static String buildJwt(ServiceAccountKey key, Instant now) {
        return Jwts.builder()
                .header()
                .add("kid", key.keyId())
                .add("typ", "JWT")
                .and()
                .issuer(key.subAccount())
                .audience()
                .add(key.tokenUri())
                .and()
                .issuedAt(java.util.Date.from(now))
                .expiration(java.util.Date.from(now.plusSeconds(JWT_TTL_SECONDS)))
                .signWith(key.privateKey(), Jwts.SIG.PS256)
                .compact();
    }
}
