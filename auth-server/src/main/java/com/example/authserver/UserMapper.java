package com.example.authserver;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface UserMapper {

	@Select("SELECT username, password, enabled FROM users WHERE username = #{username}")
	AppUser findByUsername(String username);

}
