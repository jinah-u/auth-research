package com.example.keycloak.storage;

/** sas_poc.users 한 행. */
public record LegacyUser(String username, String passwordHash, boolean enabled) {
}
