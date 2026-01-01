/**
 * Copyright © 2020–2025 Sage Creek Software. All rights reserved.
 *
 * This source code and accompanying documentation are proprietary to Sage Creek
 * Software and protected under applicable copyright and intellectual property
 * laws in Canada, the United States, and other jurisdictions.
 *
 * Unauthorized use, reproduction, modification, or distribution, in whole or in
 * part, is strictly prohibited and may result in legal action to the fullest
 * extent permitted by law.
 *
 * This software is licensed only for use by authorized parties under a valid
 * license agreement. All rights, title, and interest (including all
 * intellectual property rights) are retained by Sage Creek Software.
 *
 * For licensing inquiries, please contact: info@sagecreeksoftware.ca For more
 * information, visit: www.sagecreeksoftware.ca
 */

package ca.sagecreeksoftware.address.ws;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Main entry point for the Address Web Service Application.
 * 
 * @author Sage Creek Software
 * @version 1.0.0
 */
@SpringBootApplication
public class AddressWsApplication {

    public static void main(String[] args) {
        SpringApplication.run(AddressWsApplication.class, args);
    }

}
