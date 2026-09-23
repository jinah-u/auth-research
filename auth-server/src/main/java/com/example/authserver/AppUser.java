package com.example.authserver;

public record AppUser(String username, String password, boolean enabled) {
}
