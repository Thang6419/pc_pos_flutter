// lib/constants/handler_names.dart

abstract final class HandlerNames {
  static const String sendToCustomerDisplay = 'sendToCustomerDisplay';
  static const String requestDeviceId = 'requestDeviceId';
  static const String closeApp = 'closeApp';
  static const String toggleFullScreen = 'toggleFullScreen';
  static const String openMaximumWindow = 'openMaximumWindow';
  static const String openMinimizeWindow = 'openMinimizeWindow';
  static const String print = 'print';
}

class ReceiptTemplate {
  static const receiptHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="UTF-8" />
  <style>
    * {
      box-sizing: border-box;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }

    html,
    body {
      margin: 0;
      padding: 0;
      width: 576px;
      background: #ffffff;
        min-height: max-content;
      color: #000000;
      font-family: Arial, "Roboto", sans-serif;
        height: auto;
  min-height: 0;
  overflow: hidden;
    }

    .receipt {
      width: 576px;
      padding: 20px 18px 80px;
      background: #ffffff;
      font-size: 24px;
      line-height: 1.25;
    }

    .center {
      text-align: center;
    }

    .store-name {
      font-size: 42px;
      font-weight: 800;
      margin-bottom: 12px;
    }

    .info {
      font-size: 24px;
      margin-bottom: 4px;
    }

    .divider {
      border-top: 1px solid #000;
      margin: 16px 0;
    }

    .row {
      display: flex;
      width: 100%;
      gap: 8px;
      margin-bottom: 10px;
    }

    .head {
      font-weight: 700;
    }

    .qty {
      width: 48px;
      text-align: center;
      flex-shrink: 0;
    }

    .item {
      flex: 1;
      min-width: 0;
      word-break: break-word;
    }

    .price {
      width: 90px;
      text-align: right;
      flex-shrink: 0;
    }

    .total {
      width: 100px;
      text-align: right;
      flex-shrink: 0;
    }

    .total-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 46px;
      font-weight: 800;
      margin: 18px 0;
    }

    .payment-row {
      display: flex;
      justify-content: flex-end;
      gap: 24px;
      font-size: 32px;
      font-weight: 700;
      margin-bottom: 8px;
    }

    .footer {
      margin-top: 36px;
      font-size: 28px;
      font-weight: 700;
      text-align: center;
    }

    .date {
      margin-top: 8px;
      font-size: 24px;
      font-weight: 400;
      text-align: center;
    }
  </style>
</head>

<body>
  <div class="receipt">
    <div class="center store-name">GROCERYLY</div>
    <div class="center info">889 Watson Lane</div>
    <div class="center info">New Braunfels, TX</div>
    <div class="center info">Tel: 830-221-1234</div>

    <div class="divider"></div>

    <div class="row head">
      <div class="qty">Qty</div>
      <div class="item">Item</div>
      <div class="price">Price</div>
      <div class="total">Total</div>
    </div>

    <div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div>
<div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div><div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div><div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div><div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div><div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div><div class="row">
      <div class="qty">2</div>
      <div class="item">ONION RINGS</div>
      <div class="price">0.99</div>
      <div class="total">1.98</div>
    </div>
    <div class="row">
      <div class="qty">1</div>
      <div class="item">PIZZA</div>
      <div class="price">3.45</div>
      <div class="total">3.45</div>
    </div>

    <div class="row">
      <div class="qty">3</div>
      <div class="item">Bánh mì Sài Gòn, 1 ngàn 1 ổ</div>
      <div class="price">0.85</div>
      <div class="total">2.55</div>
    </div>
  <div class="row">
      <div class="qty">3</div>
      <div class="item">Bánh mì Sài Gòn, 1 ngàn 1 ổ</div>
      <div class="price">0.85</div>
      <div class="total">2.55</div>
    </div>
  <div class="row">
      <div class="qty">3</div>
      <div class="item">Bánh mì Sài Gòn, 1 ngàn 1 ổ</div>
      <div class="price">0.85</div>
      <div class="total">2.55</div>
    </div>
  <div class="row">
      <div class="qty">3</div>
      <div class="item">Bánh mì Sài Gòn, 1 ngàn 1 ổ</div>
      <div class="price">0.85</div>
      <div class="total">2.55</div>
    </div>
  <div class="row">
      <div class="qty">3</div>
      <div class="item">Bánh mì Sài Gòn, 1 ngàn 1 ổ</div>
      <div class="price">0.85</div>
      <div class="total">2.55</div>
    </div>

    <div class="divider"></div>

    <div class="total-row">
      <div>TOTAL</div>
      <div>$10.97</div>
    </div>

    <div class="divider"></div>

    <div class="payment-row">
      <div>Cash</div>
      <div>$15.00</div>
    </div>

    <div class="payment-row">
      <div>Change</div>
      <div>$4.03</div>
    </div>

    <div class="footer">Thank you!</div>
    <div class="date">03/16/2020 16:44</div>
  </div>
</body>
</html>
''';
}
