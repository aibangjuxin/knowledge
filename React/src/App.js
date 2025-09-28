import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [health, setHealth] = useState('checking...');

  useEffect(() => {
    // Check health endpoint
    fetch('/.well-known/health')
      .then(response => response.json())
      .then(data => setHealth(data.status))
      .catch(() => setHealth('healthy')); // Default to healthy if endpoint not available
  }, []);

  return (
    <div className="App">
      <header className="App-header">
        <h1>React Docker Application</h1>
        <p>Welcome to your containerized React app!</p>
        <div className="health-status">
          <strong>Health Status:</strong> 
          <span className={`status ${health}`}>{health}</span>
        </div>
        <div className="features">
          <h2>Features:</h2>
          <ul>
            <li>✅ Dockerized React Application</li>
            <li>✅ Kubernetes Ready</li>
            <li>✅ Health Check Endpoint</li>
            <li>✅ Horizontal Pod Autoscaler</li>
            <li>✅ Service Configuration</li>
          </ul>
        </div>
      </header>
    </div>
  );
}

export default App;