package com.example.keycloak.storage;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * 기존 회원 테이블(sas_poc.users) 조회. 데모이므로 커넥션 풀 없이 요청마다 연결한다.
 */
public class LegacyUserRepository {

	private static final String SELECT = "SELECT username, password, enabled FROM users";

	private final String url;

	private final String user;

	private final String password;

	public LegacyUserRepository(String url, String user, String password) {
		this.url = url;
		this.user = user;
		this.password = password;
	}

	public Optional<LegacyUser> findByUsername(String username) {
		return query(SELECT + " WHERE username = ?", username).stream().findFirst();
	}

	public List<LegacyUser> search(String keyword, int first, int max) {
		String like = "%" + (keyword == null ? "" : keyword.replace("*", "")) + "%";
		return query(SELECT + " WHERE username LIKE ? ORDER BY username LIMIT " + Math.max(max, 0) + " OFFSET "
				+ Math.max(first, 0), like);
	}

	public int count() {
		try (Connection conn = connect();
				PreparedStatement ps = conn.prepareStatement("SELECT COUNT(*) FROM users");
				ResultSet rs = ps.executeQuery()) {
			return rs.next() ? rs.getInt(1) : 0;
		}
		catch (SQLException e) {
			throw new IllegalStateException("legacy users count failed", e);
		}
	}

	private List<LegacyUser> query(String sql, String param) {
		try (Connection conn = connect(); PreparedStatement ps = conn.prepareStatement(sql)) {
			ps.setString(1, param);
			try (ResultSet rs = ps.executeQuery()) {
				List<LegacyUser> result = new ArrayList<>();
				while (rs.next()) {
					result.add(new LegacyUser(rs.getString(1), rs.getString(2), rs.getBoolean(3)));
				}
				return result;
			}
		}
		catch (SQLException e) {
			throw new IllegalStateException("legacy users query failed", e);
		}
	}

	private Connection connect() throws SQLException {
		return DriverManager.getConnection(url, user, password);
	}

}
