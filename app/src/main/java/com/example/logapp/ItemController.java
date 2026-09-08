package com.example.logapp;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
public class ItemController {

    private final JdbcTemplate jdbcTemplate;

    // Spring이 DB 연결(JdbcTemplate)을 자동으로 넣어줌
    public ItemController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    // 정상 엔드포인트: items 테이블 조회 → JSON 반환
    @GetMapping("/items")
    public List<Map<String, Object>> getItems() {
        // DB에 SQL 쿼리. MySQL이 죽어 있으면 여기서 커넥션 예외 발생
        return jdbcTemplate.queryForList("SELECT id, name FROM items");
    }

    // 헬스체크용 (DB 안 거침)
    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
