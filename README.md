# TS

[![Build Status](https://travis-ci.org/prasadtalasila/TransportScheduler.svg?branch=master)](https://travis-ci.org/prasadtalasila/TransportScheduler) [![Coverage Status](https://coveralls.io/repos/github/prasadtalasila/TransportScheduler/badge.svg?branch=master)](https://coveralls.io/github/prasadtalasila/TransportScheduler?branch=master) [![Code Climate](https://codeclimate.com/github/prasadtalasila/TransportScheduler/badges/gpa.svg)](https://codeclimate.com/github/prasadtalasila/TransportScheduler)

TransportScheduler application dependencies:   
GenStateMachine for station FSM and GenServer for IPC.   
Maru for RESTful API implementation.   
Edeliver using Distillery for building releases and deployment.   

Other packages used:   
ExCoveralls for test coverage.   
ExProf for profiling.   
Credo for code quality.   


## Usage

Run the following commands to compile:
```bash
cd TransportScheduler
mix deps.get
mix compile
mix test
```

Run the following command to build a release:
```bash
mix release
```

Run the following command to run the application interactively:
```bash
_build/dev/rel/ts/bin/ts console
```

Issue the following cURL command for initialisation of the network:
```bash
curl http://localhost:8880/api
```

For testing the API, following cURL commands are issued to:

1. Obtain Schedule of a Station:  
```bash
curl -X GET 'http://localhost:8880/api/station/schedule?station_code=%STATION_CODE%&date=%DATE%'
```  
where `%STATION_CODE%` is a positive integer indicating the station code of the source and `%DATE%` is the date of travel in the format 'dd-mm-yyyy'.

2. Obtain State of a Station:  
```bash
curl -X GET 'http://localhost:8880/api/station/state?station_code=%STATION_CODE%'
```  
where `%STATION_CODE%` is a positive integer indicating the required station code.

Run the following commands to deploy (currently server and user are localhost): **UNTESTED**    
```bash
mix edeliver build release
mix edeliver deploy release
```

Run the following command to start application: **UNTESTED**   
```bash
mix edeliver start
```

## Benchmark Tests

For running the respective benchmarks (async/synchronous), use
```bash
mix sync_benchmark
mix async_benchmark
```

A shell script for running the synchronous benchmark multiple times is:
```bash
for i in $(seq 1 $n); do mix benchmark [2>/dev/null | grep -C 2 "^Start time: "]; done [> ~/file.out]
```
where `$n` is the number of random queries over which the benchmark must be run. `file.out` is the file that will store the log thus generated by the benchmark. The portion of the command in [square brackets] is optional.

Automatically, three files `async_test.csv`, `sync_test.csv` and `times.csv` are created in the `data/` directory.