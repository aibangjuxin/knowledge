package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/mux"
)

type App struct {
	DB     *sql.DB
	Config Config
}

type Config struct {
	DBHost                string
	DBPort                string
	DBName                string
	DBUser                string
	DBPassword            string
	DBMaxConnections      int
	DBMaxIdleConnections  int
	DBConnectionTimeout   time.Duration
	DBConnectionLifetime  time.Duration
	AppPort               string
	LogLevel              string
	Environment           string
}

type HealthResponse struct {
	Status    string            `json:"status"`
	Timestamp string            `json:"timestamp"`
	Version   string            `json:"version"`
	Database  DatabaseStatus    `json:"database"`
	Pod       PodInfo          `json:"pod"`
}

type DatabaseStatus struct {
	Connected     bool   `json:"connected"`
	ResponseTime  string `json:"response_time"`
	ActiveConns   int    `json:"active_connections"`
	IdleConns     int    `json:"idle_connections"`
}

type PodInfo struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	IP        string `json:"ip"`
}

type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

func main() {
	config := loadConfig()
	
	app := &App{
		Config: config,
	}

	// 初始化数据库连接
	if err := app.initDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer app.DB.Close()

	// 初始化数据库表
	if err := app.initTables(); err != nil {
		log.Printf("Warning: Failed to initialize tables: %v", err)
	}

	// 设置路由
	router := app.setupRoutes()

	// 启动服务器
	log.Printf("Starting server on port %s", config.AppPort)
	log.Printf("Environment: %s", config.Environment)
	log.Printf("Database: %s:%s/%s", config.DBHost, config.DBPort, config.DBName)
	
	if err := http.ListenAndServe(":"+config.AppPort, router); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func loadConfig() Config {
	config := Config{
		DBHost:               getEnv("DB_HOST", "localhost"),
		DBPort:               getEnv("DB_PORT", "3306"),
		DBName:               getEnv("DB_NAME", "appdb"),
		DBUser:               getEnv("DB_USER", "root"),
		DBPassword:           getEnv("DB_PASSWORD", ""),
		DBMaxConnections:     getEnvInt("DB_MAX_CONNECTIONS", 10),
		DBMaxIdleConnections: getEnvInt("DB_MAX_IDLE_CONNECTIONS", 5),
		DBConnectionTimeout:  getEnvDuration("DB_CONNECTION_TIMEOUT", "30s"),
		DBConnectionLifetime: getEnvDuration("DB_CONNECTION_MAX_LIFETIME", "300s"),
		AppPort:              getEnv("APP_PORT", "8080"),
		LogLevel:             getEnv("LOG_LEVEL", "info"),
		Environment:          getEnv("ENVIRONMENT", "development"),
	}
	return config
}

func (app *App) initDB() error {
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local&timeout=%s",
		app.Config.DBUser,
		app.Config.DBPassword,
		app.Config.DBHost,
		app.Config.DBPort,
		app.Config.DBName,
		app.Config.DBConnectionTimeout,
	)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}

	// 配置连接池
	db.SetMaxOpenConns(app.Config.DBMaxConnections)
	db.SetMaxIdleConns(app.Config.DBMaxIdleConnections)
	db.SetConnMaxLifetime(app.Config.DBConnectionLifetime)

	// 测试连接
	if err := db.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	app.DB = db
	log.Println("Database connection established successfully")
	return nil
}

func (app *App) initTables() error {
	createTableSQL := `
	CREATE TABLE IF NOT EXISTS users (
		id INT AUTO_INCREMENT PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		email VARCHAR(100) UNIQUE NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;`

	if _, err := app.DB.Exec(createTableSQL); err != nil {
		return fmt.Errorf("failed to create users table: %w", err)
	}

	// 插入示例数据
	insertSQL := `
	INSERT IGNORE INTO users (name, email) VALUES 
	('Alice Johnson', 'alice@example.com'),
	('Bob Smith', 'bob@example.com'),
	('Charlie Brown', 'charlie@example.com');`

	if _, err := app.DB.Exec(insertSQL); err != nil {
		log.Printf("Warning: Failed to insert sample data: %v", err)
	}

	return nil
}

func (app *App) setupRoutes() *mux.Router {
	router := mux.NewRouter()

	// 健康检查端点
	router.HandleFunc("/health", app.healthHandler).Methods("GET")
	router.HandleFunc("/ready", app.readinessHandler).Methods("GET")

	// API 端点
	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/users", app.getUsersHandler).Methods("GET")
	api.HandleFunc("/users", app.createUserHandler).Methods("POST")
	api.HandleFunc("/users/{id}", app.getUserHandler).Methods("GET")
	api.HandleFunc("/db-stats", app.getDBStatsHandler).Methods("GET")

	// 根路径
	router.HandleFunc("/", app.rootHandler).Methods("GET")

	return router
}

func (app *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	
	// 测试数据库连接
	dbStatus := DatabaseStatus{Connected: false}
	if err := app.DB.Ping(); err == nil {
		dbStatus.Connected = true
		dbStatus.ResponseTime = time.Since(start).String()
		
		// 获取连接池统计
		stats := app.DB.Stats()
		dbStatus.ActiveConns = stats.OpenConnections
		dbStatus.IdleConns = stats.Idle
	}

	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now().Format(time.RFC3339),
		Version:   "1.0.0",
		Database:  dbStatus,
		Pod: PodInfo{
			Name:      getEnv("POD_NAME", "unknown"),
			Namespace: getEnv("POD_NAMESPACE", "unknown"),
			IP:        getEnv("POD_IP", "unknown"),
		},
	}

	if !dbStatus.Connected {
		response.Status = "unhealthy"
		w.WriteHeader(http.StatusServiceUnavailable)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (app *App) readinessHandler(w http.ResponseWriter, r *http.Request) {
	// 简单的就绪检查
	if err := app.DB.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "not ready",
			"error":  err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ready",
	})
}

func (app *App) getUsersHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := app.DB.Query("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		users = append(users, user)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

func (app *App) createUserHandler(w http.ResponseWriter, r *http.Request) {
	var user User
	if err := json.NewDecoder(r.Body).Decode(&user); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	result, err := app.DB.Exec("INSERT INTO users (name, email) VALUES (?, ?)", user.Name, user.Email)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	id, _ := result.LastInsertId()
	user.ID = int(id)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

func (app *App) getUserHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	var user User
	err := app.DB.QueryRow("SELECT id, name, email, created_at FROM users WHERE id = ?", id).
		Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	
	if err == sql.ErrNoRows {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func (app *App) getDBStatsHandler(w http.ResponseWriter, r *http.Request) {
	stats := app.DB.Stats()
	
	response := map[string]interface{}{
		"max_open_connections":     stats.MaxOpenConnections,
		"open_connections":         stats.OpenConnections,
		"in_use":                  stats.InUse,
		"idle":                    stats.Idle,
		"wait_count":              stats.WaitCount,
		"wait_duration":           stats.WaitDuration.String(),
		"max_idle_closed":         stats.MaxIdleClosed,
		"max_idle_time_closed":    stats.MaxIdleTimeClosed,
		"max_lifetime_closed":     stats.MaxLifetimeClosed,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (app *App) rootHandler(w http.ResponseWriter, r *http.Request) {
	response := map[string]interface{}{
		"service":     "PSC Demo Application",
		"version":     "1.0.0",
		"environment": app.Config.Environment,
		"endpoints": map[string]string{
			"health":    "/health",
			"ready":     "/ready",
			"users":     "/api/v1/users",
			"db_stats":  "/api/v1/db-stats",
		},
		"pod": PodInfo{
			Name:      getEnv("POD_NAME", "unknown"),
			Namespace: getEnv("POD_NAMESPACE", "unknown"),
			IP:        getEnv("POD_IP", "unknown"),
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// 辅助函数
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func getEnvDuration(key string, defaultValue string) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	duration, _ := time.ParseDuration(defaultValue)
	return duration
}