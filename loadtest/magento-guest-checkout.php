<?php
// Verbatim copy of the checkout scenario in the blog post, produced by
// sync-from-article.sh. Edit the post, not this file.
require __DIR__."/../vendor/autoload.php";

use VoltTest\DataSourceConfiguration;
use VoltTest\VoltTest;

$base = rtrim(getenv('TARGET_URL') ?: 'https://magento.test', '/');

$test = (new VoltTest('Magento guest checkout'))
    ->target($base)
    ->setVirtualUsers((int) (getenv('VUS') ?: 20))
    ->setDuration(getenv('DURATION') ?: '2m')
    ->setRampUp('30s');

$address = '{"firstname":"Load","lastname":"Test","street":["1 Test St"],'
    . '"city":"Los Angeles","region":"CA","region_id":12,"region_code":"CA",'
    . '"country_id":"US","postcode":"90001","telephone":"5555555555","email":"${email}"}';

$checkout = $test->scenario('Guest checkout via REST')
    ->setWeight(5)
    ->setThinkTime('2s')
    ->autoHandleCookies()
    ->setDataSourceConfiguration(
        new DataSourceConfiguration(__DIR__.'/data/skus.csv', 'random', true)
    );

$checkout->step('Create guest cart')
    ->post("$base/rest/V1/guest-carts")
    ->header('Content-Type', 'application/json')
    ->validateStatus('cart created', 200)
    ->extractFromRegex('cart_id', '^"([A-Za-z0-9]+)"$');

$checkout->step('Add item')
    ->post("$base/rest/V1/guest-carts/\${cart_id}/items",
        '{"cartItem":{"sku":"${sku}","qty":1,"quote_id":"${cart_id}"}}')
    ->header('Content-Type', 'application/json')
    ->validateStatus('item added', 200);

$checkout->step('Estimate shipping')
    ->post("$base/rest/V1/guest-carts/\${cart_id}/estimate-shipping-methods",
        '{"address":{"country_id":"US","region_id":12,"postcode":"90001"}}')
    ->header('Content-Type', 'application/json')
    ->validateStatus('shipping estimated', 200);

$checkout->step('Set shipping information')
    ->post("$base/rest/V1/guest-carts/\${cart_id}/shipping-information",
        '{"addressInformation":{"shipping_address":'.$address.',"billing_address":'.$address.','
        . '"shipping_carrier_code":"flatrate","shipping_method_code":"flatrate"}}')
    ->header('Content-Type', 'application/json')
    ->validateStatus('shipping set', 200);

$checkout->step('Place order')
    ->post("$base/rest/V1/guest-carts/\${cart_id}/payment-information",
        '{"email":"${email}","paymentMethod":{"method":"checkmo"},"billing_address":'.$address.'}')
    ->header('Content-Type', 'application/json')
    ->validateStatus('order placed', 200)
    ->extractFromRegex('order_id', '^"?([0-9]+)"?$');

$test->run(true);
