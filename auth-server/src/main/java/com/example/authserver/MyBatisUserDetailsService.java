package com.example.authserver;

import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class MyBatisUserDetailsService implements UserDetailsService {

	private final UserMapper userMapper;

	public MyBatisUserDetailsService(UserMapper userMapper) {
		this.userMapper = userMapper;
	}

	@Override
	public UserDetails loadUserByUsername(String username) {
		AppUser user = userMapper.findByUsername(username);
		if (user == null) {
			throw new UsernameNotFoundException(username);
		}
		return User.withUsername(user.username())
				.password(user.password())
				.disabled(!user.enabled())
				.authorities("ROLE_USER")
				.build();
	}

}
