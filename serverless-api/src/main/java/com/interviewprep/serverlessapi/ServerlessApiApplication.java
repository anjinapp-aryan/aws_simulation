package com.interviewprep.serverlessapi;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class ServerlessApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(ServerlessApiApplication.class, args);
    }
}
