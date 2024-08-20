<?php
header("Access-Control-Allow-Origin: link");

define('SECRET_KEY', '');

function returnError($message) {
    echo json_encode(['errors' => $message]);
    exit();
}

function getCachedOrders() {
    return json_decode(file_get_contents('cached_orders.json'), true) ?: [];
}

function handlePostRequest() {
    if (!isset($_POST['orderId']) || !isset($_POST['username'])) {
        returnError("Invalid Request!");
    }

    $orderId = $_POST['orderId'];
    $username = $_POST['username'];

    if (isDuplicateOrder($orderId)) {
        returnError("Order already exists!");
    }

    if (!is_numeric($orderId)) {
        returnError("Invalid Order ID!");
    }

    $usernamePattern = '/^(?!_)(?!.*__)[a-zA-Z0-9_]{3,20}(?<!_)$/';
    if (!preg_match($usernamePattern, $username)) {
        returnError("Invalid Username!");
    }

    cacheOrder($username, $orderId);
}

function isDuplicateOrder($orderId) {
    $cachedOrders = getCachedOrders();
    foreach ($cachedOrders as $order) {
        if ($order['orderId'] == $orderId) {
            return true;
        }
    }
    return false;
}

function cacheOrder($username, $orderId) {
    $config = include('config.php');
    $api_key = $config['api_key'];
    $url = $config['shopify_domain'];

    $ch = curl_init("$url/orders/$orderId.json");
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    curl_setopt($ch, CURLOPT_HTTPHEADER, array(
        "X-Shopify-Access-Token: $api_key",
        'Content-Type: application/json'
    ));

    $response = curl_exec($ch);

    if (curl_errno($ch)) {
        returnError('Shopify request error');
    }

    curl_close($ch);
    
    $orderData = json_decode($response, true);

    if (!isset($orderData["order"])) {
        returnError("Invalid Shopify response. Order not found.");
    }

    $productIds = array_map(function($item) {
        return $item['product_id'];
    }, $orderData["order"]['line_items']);

    $productData = json_decode(file_get_contents('productIds.json'), true);
    $items = [];

    foreach ($productIds as $productId) {
        if (isset($productData[$productId])) {
            $items = array_merge($items, $productData[$productId]);
        }
    }

    $cachedOrders = getCachedOrders();
    $cachedOrders[] = array(
        'username' => $username,
        'orderId' => $orderId,
        'items' => $items,
        'orderComplete' => false,
        'orderTotal' => $orderData["order"]['total_price']
    );

    file_put_contents('cached_orders.json', json_encode($cachedOrders));
    echo json_encode(['data' => "Order $orderId cached successfully!"]);
    exit();
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    handlePostRequest();
} elseif ($_SERVER["REQUEST_METHOD"] == "GET") {
    handleGetRequest();
} else {
    returnError("Invalid Request Method!");
}
?>
