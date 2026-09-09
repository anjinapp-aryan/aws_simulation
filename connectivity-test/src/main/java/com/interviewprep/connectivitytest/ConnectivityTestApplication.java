package com.interviewprep.connectivitytest;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class ConnectivityTestApplication {

    public static void main(String[] args) {
        SpringApplication.run(ConnectivityTestApplication.class, args);
    }
}
