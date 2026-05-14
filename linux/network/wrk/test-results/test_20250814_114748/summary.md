# Load Test Summary Report

**Test Target:** https://www.toutiao.com/w/1840396364175372/?log_from=386af56e4fc548_1755142542314  
**Test Date:** Thu Aug 14 11:49:19 CST 2025  
**Duration:** 60s  
**Connections:** 10  
**Requests:** 1000  

## Test Configuration
- Tools Used: wrk ab hey
- Output Directory: ./test-results/test_20250814_114748

## Results

### wrk Results
```
Running 1m test @ https://www.toutiao.com/w/1840396364175372/?log_from=386af56e4fc548_1755142542314
  2 threads and 10 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    67.78ms   19.12ms 346.76ms   88.37%
    Req/Sec    74.49     16.64   101.00     73.01%
  8917 requests in 1.00m, 628.51MB read
Requests/sec:    148.36
Transfer/sec:     10.46MB
```

### ab Results
```
This is ApacheBench, Version 2.3 <$Revision: 1913912 $>
Copyright 1996 Adam Twiss, Zeus Technology Ltd, http://www.zeustech.net/
Licensed to The Apache Software Foundation, http://www.apache.org/

Benchmarking www.toutiao.com (be patient)
Completed 100 requests
Completed 200 requests
Completed 300 requests
Completed 400 requests
Completed 500 requests
Completed 600 requests
Completed 700 requests
Completed 800 requests
Completed 900 requests
Completed 1000 requests
Finished 1000 requests


Server Software:        Tengine
Server Hostname:        www.toutiao.com
```

### hey Results
```

Summary:
  Total:	7.1341 secs
  Slowest:	0.2468 secs
  Fastest:	0.0424 secs
  Average:	0.0669 secs
  Requests/sec:	140.1725
  

Response time histogram:
  0.042 [1]	|
  0.063 [629]	|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.083 [261]	|■■■■■■■■■■■■■■■■■
  0.104 [29]	|■■
  0.124 [32]	|■■
  0.145 [24]	|■■
  0.165 [9]	|■
  0.185 [6]	|
  0.206 [5]	|
  0.226 [2]	|
```

