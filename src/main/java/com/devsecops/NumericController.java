package com.devsecops;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@RestController
public class NumericController {

	private final Logger logger = LoggerFactory.getLogger(getClass());

	// Externalisé dans application.properties : évite de recompiler pour
	// changer l'URL du node-service selon l'environnement (dev/prod).
	@Value("${node.service.url:http://localhost:5000/plusone}")
	private String baseURL;

	private final RestTemplate restTemplate = new RestTemplate();

	@GetMapping("/")
	public String welcome() {
		return "Kubernetes DevSecOps";
	}

	@GetMapping("/compare/{value}")
	public String compareToFifty(@PathVariable int value) {
		return value > 50 ? "Greater than 50" : "Smaller than or equal to 50";
	}

	@GetMapping("/increment/{value}")
	public int increment(@PathVariable int value) {
		ResponseEntity<String> responseEntity = restTemplate.getForEntity(baseURL + '/' + value, String.class);
		String response = responseEntity.getBody();
		logger.info("Value Received in Request - " + value);
		logger.info("Node Service Response - " + response);
		return Integer.parseInt(response);
	}
}
