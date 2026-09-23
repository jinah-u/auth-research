package com.example.authserver;

import javax.sql.DataSource;

import org.apache.ibatis.session.SqlSessionFactory;
import org.mybatis.spring.SqlSessionFactoryBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * mybatis-spring-boot-starter 3.0.4의 MybatisAutoConfiguration이 Boot 4.1의
 * DataSourceAutoConfiguration보다 먼저 평가되어(@AutoConfigureAfter 순서 불일치) SqlSessionFactory 빈이
 * 자동 생성되지 않는 문제가 있어, 이 프로젝트에서는 SqlSessionFactory를 직접 정의한다.
 */
@Configuration
public class MyBatisConfig {

	@Bean
	public SqlSessionFactory sqlSessionFactory(DataSource dataSource) throws Exception {
		SqlSessionFactoryBean factoryBean = new SqlSessionFactoryBean();
		factoryBean.setDataSource(dataSource);
		return factoryBean.getObject();
	}

}
