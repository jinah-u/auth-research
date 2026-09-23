INSERT INTO users (username, password, enabled) VALUES
    ('user', '{bcrypt}$2a$10$uHXTKe0rG/Hl0Q9OlE6dLe19JW72BJVTh8WMvt1yPy6GjGkJloqaS', TRUE)
ON DUPLICATE KEY UPDATE password = VALUES(password);
