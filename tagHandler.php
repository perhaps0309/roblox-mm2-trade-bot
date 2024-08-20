<?php
header("Access-Control-Allow-Origin: linkhertelorerelrlerleorelr");
function returnError($message) {
    echo json_encode(['errors' => $message]);
    exit();
}

function isDuplicateOrder($orderId) {
    $cachedOrders = json_decode(file_get_contents('cached_orders.json'), true);
    foreach ($cachedOrders as $order) {
        if ($order['orderId'] == $orderId) {
            return true;
        }
    }
    return false;
}

if ($_SERVER["REQUEST_METHOD"] != "POST" && $_SERVER["REQUEST_METHOD"] != "GET") {
    returnError("Invalid Request! Reason: 1D");
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    if (!isset($_POST['orderId']) && $_SERVER["REQUEST_METHOD"] == "POST") {
        returnError("Invalid Request! Reason: 2D");
    } else if (!isset($_POST['userid']) && $_SERVER["REQUEST_METHOD"] == "POST") {
        returnError("Invalid Request! Reason: 3D");
    }

    if (isDuplicateOrder($_POST['orderId'])) {
        returnError("Invalid Request! Reason: 1E");
    }
}

if ($_SERVER["REQUEST_METHOD"] == "GET") {
    if (isset($_GET["setOrderComplete"])) { // Modify the cache and set orderComplete to true
        $cachedOrders = json_decode(file_get_contents('cached_orders.json'), true);
        $orderId = $_GET["setOrderComplete"];

        foreach ($cachedOrders as $index => $order) {
            if ($order['orderId'] == $orderId) {
                $cachedOrders[$index]['orderComplete'] = true;
                break;
            }
        }

        file_put_contents('cached_orders.json', json_encode($cachedOrders));
        echo json_encode(['data' => "Order $orderId marked as complete!"]);
        exit();
    }

    if (isset($_GET["pendingRequests"])) { // check if pendingRequest.txt is set to true
        $pendingRequests = file_get_contents('pendingRequest.txt');
        echo json_encode(['data' => $pendingRequests]);
        exit();
    }

    if (isset($_GET["setPendingRequests"])) { // set pendingRequest.txt to true or false
        // check if pendingRequest.txt is set to false, then set to true and if secretKey is correct set to false

        if (isset($_GET["secretKey"]) && $_GET['secretKey'] == '') { // yes i hardcoded the secret key, security is not a concern here as this is only ran on the server.
            file_put_contents('pendingRequest.txt', 'false');
            echo json_encode(['data' => 'Pending requests set to false!']);
            exit();
        } else {
            file_put_contents('pendingRequest.txt', 'true');
            echo json_encode(['data' => 'Pending requests set to true!']);
            exit();
        }
    }

    if (!isset($_GET['getShopifyOrders']) || $_GET['getShopifyOrders'] != 'true') {
        returnError("Invalid Request! Reason: 5D");
    } else if (!isset($_GET['secretKey']) || $_GET['secretKey'] != '') {
        returnError("Invalid Request! Reason: 6D");
    } 

    $cachedOrders = json_decode(file_get_contents('cached_orders.json'), true);
    echo json_encode(['data' => $cachedOrders]);

    exit();
}
 
// Check if orderId is a number 

if (!is_numeric($_POST['orderId'])) {
    returnError("Invalid Request! Reason: 2D");
}

if (!is_numeric($_POST['userid'])) {
    returnError("Invalid Request! Reason: 3D");
}

$ip = $_SERVER['REMOTE_ADDR'];
$currentTime = time();

// Load rate limit data
$ipRateLimit = json_decode(file_get_contents('ip_ratelimit.json'), true);
if (isset($ipRateLimit[$ip]) && $ipRateLimit[$ip]['timeout'] > $currentTime) {
    returnError("Rate limited! Reason: " . $ipRateLimit[$ip]['reason']);
}

// Load shopify queue
$shopifyQueue = json_decode(file_get_contents('shopify_queue.json'), true);

$ordersByIp = array_filter($shopifyQueue, function($order) use ($ip) {
    return $order['ip'] == $ip;
});

$recentOrdersByIp = array_filter($ordersByIp, function($order) use ($currentTime) {
    return $currentTime - $order['time'] < 15;
});

if (count($recentOrdersByIp) > 0) {
    $ipRateLimit[$ip]['timeout'] = $currentTime + 30;  // Set a timeout for 30 seconds
    $ipRateLimit[$ip]['reason'] = '1C';
    file_put_contents('ip_ratelimit.json', json_encode($ipRateLimit));
    returnError("Rate limited! Reason: 1C");
}

// Check if the order is already in the queue

$ordersById = array_filter($shopifyQueue, function($order) use ($ip) {
    return $order['orderId'] == $_POST['orderId'];
});

if (count($ordersById) > 0) {
    $ipRateLimit[$ip]['timeout'] = $currentTime + 15;  // Set a timeout for 15 seconds
    $ipRateLimit[$ip]['reason'] = '4D';
    file_put_contents('ip_ratelimit.json', json_encode($ipRateLimit));
    returnError("Rate limited! Reason: 4D");
}

// Add the order to the queue

$shopifyQueue[] = ['ip' => $ip, 'time' => $currentTime, 'userid' => $_POST['userid'], 'orderId' => $_POST['orderId']];
file_put_contents('shopify_queue.json', json_encode($shopifyQueue));

// Background worker for processing the Shopify queue
while (count($shopifyQueue) > 0) {
    $nextOrder = array_shift($shopifyQueue);
    if ($currentTime - $nextOrder['time'] < 5) {
        sleep(5);
    }

    cacheOrder($nextOrder['userid'], $nextOrder['orderId']);

    file_put_contents('shopify_queue.json', json_encode($shopifyQueue));
}

function removeShopifyQueue($orderId) {
    $shopifyQueue = json_decode(file_get_contents('shopify_queue.json'), true);
    $shopifyQueue = array_filter($shopifyQueue, function($order) use ($orderId) {
        return $order['orderId'] != $orderId;
    });

    file_put_contents('shopify_queue.json', json_encode($shopifyQueue));
}

function cacheOrder($userid, $orderId) {
    $config = include('config.php');  // Load configurations from the config.php file
    $api_key = $config['api_key'];
    $url = $config['shopify_domain'];

    // Set up cURL to fetch order details from Shopify
    $ch = curl_init("$url/orders/$orderId.json");
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true); // Follow redirects (needed for Shopify)
    curl_setopt($ch, CURLOPT_HTTPHEADER, array(
        "X-Shopify-Access-Token: $api_key",
        'Content-Type: application/json'
    ));
    $response = curl_exec($ch);

    removeShopifyQueue($orderId);
    if (curl_errno($ch)) {
        returnError('Shopify request error');
    }

    curl_close($ch);

    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    if ($httpCode != 200) {
        returnError('Unexpected HTTP response: ' . $httpCode);
    }
    
    $orderData = json_decode($response, true);
    if ($orderData == null && json_last_error() !== JSON_ERROR_NONE) {
        returnError('JSON decode error: ' . json_last_error_msg());
    }
    
    if ($orderData['errors'] != null) {
        returnError("Rate limited! Reason: 1B");
    }

    // Get the line items from the order data
    $lineItems = $orderData["order"]['line_items'];

    $productData = json_decode(file_get_contents('productIds.json'), true);
    $items = [];

    // Loop through the line items
    foreach ($lineItems as $lineItem) {
        $productId = $lineItem['product_id'];
        $quantity = $lineItem['quantity']; // Get the quantity ordered

        // Check if the product ID exists in the product data
        if (isset($productData[$productId])) {
            foreach ($productData[$productId] as $productName => $productValue) {
                // Check if the product name already exists in $items
                if (isset($items[$productName])) {
                    $items[$productName] += $quantity;
                } else {
                    $items[$productName] = $quantity;
                }
            }
        }
    }

    // Store the order data in cached_orders.json
    $cachedOrders = json_decode(file_get_contents('cached_orders.json'), true);
    $cachedOrders[] = array(
        'userid' => $userid,
        'orderId' => $orderId,
        'items' => $items,
        'orderComplete' => false,
        'orderTotal' => $orderData["order"]['total_price']
    );

    file_put_contents('cached_orders.json', json_encode($cachedOrders));

    // Remove the order from the IP rate limit

    $ipRateLimit = json_decode(file_get_contents('ip_ratelimit.json'), true);
    unset($ipRateLimit[$ip]);

    file_put_contents('ip_ratelimit.json', json_encode($ipRateLimit));

    // Return that the order was cached successfully

    echo json_encode(['data' => "Order $orderId cached successfully!"]);
}
?>
