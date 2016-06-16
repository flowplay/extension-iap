package extension.iap.android;

import extension.iap.IAP;
import flash.errors.Error;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.Lib;
import haxe.Json;

import openfl.utils.JNI;

/**
 * Provides convenience methods and properties for in-app purchases (Android & iOS).
 * The methods and properties are static, so there's no need to instantiate an instance,
 * but an initialization is required prior to the first use.
 * Every method is asynchronous (non-blocking). The callbacks always fire events indicating
 * the success or failure of every operation.
 *
 * The first step is to initialize the extension. You do so by calling the {@link #initialize}
 * method. The result comes with a PURCHASE_INIT or PURCHASE_INIT_FAILED IAPEvent. Also, the
 * available property will tell if you can use the extension at any time.
 *
 * Although we aim to provide a unified API for every target, there are some differences that
 * required to leave platform exclusive methods and properties. So you'll find different workflows.
 *
 * Android workflow:
 * ----------------
 *
 * After initialization is complete, you will typically want to request an inventory of owned
 * items and subscriptions. See {@link #queryInventory} and related events. This method can also be
 * used to retrieve a detailed list of products.
 *
 * Then you may want to buy items with the {@link #purchase} method, and if the item is consumable,
 * the {@link #consume} method should be called after a successful purchase.
 *
 * iOS workflow:
 * ------------
 *
 * After initialization is complete, you will typically want request details about the products
 * being sold {@link #requestProductData}, and also probably try to restore non consumable
 * items previously purchased by the user using the {@link #restore} method.
 *
 * Then you may want to buy items with the {@link #purchase} method. You don't need to call the
 * consume method for iOS, but for consumable items you may want to locally erase the purchase from
 * the Inventory.
 *
 * You may want to check the IAPEvent, Purchase and ProductDetails classes to explore further.
 *
 */

@:allow(extension.iap) class IAP {

	public static var available (get, null):Bool;
	public static var manualTransactionMode (get, set):Bool;
	public static var inventory(default, null):Inventory = null;
	private static var initialized = false;
	private static var tempProductsData:Array<IAProduct> = [];

	// Event dispatcher composition
	private static var dispatcher = new EventDispatcher ();

	/**
	 * Initializes the extension.
	 *
	 * @param publicKey (Android). Your application's public key, encoded in base64.
	 *     This is used for verification of purchase signatures. You can find your app's base64-encoded
	 *     public key in your application's page on Google Play Developer Console. Note that this
	 *     is NOT your "developer public key".
	 *
	 * Related Events (IAPEvent):
	 * 		PURCHASE_INIT: Fired when the initialization was successful
	 * 		PURCHASE_INIT_FAILED: Fired when the initialization failed
	 */

	public static function initialize (publicKey:String = ""):Void {

		if (funcInit == null) {
            #if kindle
            funcInit = JNI.createStaticMethod ("org/haxe/extension/iap/amazon/InAppPurchase", "initialize", "(Ljava/lang/String;Lorg/haxe/lime/HaxeObject;)V");
            #else
            funcInit = JNI.createStaticMethod ("org/haxe/extension/iap/InAppPurchase", "initialize", "(Ljava/lang/String;Lorg/haxe/lime/HaxeObject;)V");
            #end
		}

		if (inventory == null) inventory = new Inventory(null);
		funcInit (publicKey, new IAPHandler ());
	}

	/**
	 * Sends a purchase intent for a given product.
	 *
	 * @param productID (iOS & Android). The unique Id for the desired product (Android Sku).
	 * @param devPayload (Android). Extra data (developer payload), which will be returned with the purchase data
	 *     when the purchase completes. This extra data will be permanently bound to that purchase
	 *     and will always be returned when the purchase is queried.
	 *
	 * Related Events (IAPEvent):
	 * 		PURCHASE_SUCCESS: Fired when the purchase attempt was successful
	 * 		PURCHASE_FAILURE: Fired when the purchase attempt failed
	 * 		PURCHASE_CANCEL: Fired when the purchase attempt was cancelled by the user
	 */

	public static function purchase (productID:String, devPayload:String = ""):Void {

		if (funcBuy == null) {
            #if kindle
            funcBuy = JNI.createStaticMethod ("org/haxe/extension/iap/amazon/InAppPurchase", "buy", "(Ljava/lang/String;Ljava/lang/String;)V");
            #else
            funcBuy = JNI.createStaticMethod ("org/haxe/extension/iap/InAppPurchase", "buy", "(Ljava/lang/String;Ljava/lang/String;)V");
            #end
		}

		IAPHandler.lastPurchaseRequest = productID;
		funcBuy (productID, devPayload);
	}


	/**
	 * Retrieves localized information about a list of products.
	 * 
	 * @param inArg. A String with the product Id, or an Array of Strings with multiple product Ids.
	 * 
	 * Related Events (IAPEvent): 
	 * 		PURCHASE_PRODUCT_DATA_COMPLETE: Fired when the products data has been retrieved. 
	 * 			The event will come with a productsData array.
	 * 			This method also populates the productDetailsMap property of the inventory, so it can be accessed anytime after calling it.
	 */
	
	public static function requestProductData (inArg:Dynamic) : Void { }

	/**
	 * Sends a consume intent for a given product.
	 *
	 * @param purchase. The previously purchased product.
	 *
	 * Related Events (IAPEvent):
	 * 		PURCHASE_CONSUME_SUCCESS: Fired when the consume attempt was successful
	 * 		PURCHASE_CONSUME_FAILURE: Fired when the consume attempt failed
	 */

	public static function consume (purchase:Purchase):Void {

		if (funcConsume == null) {
            #if kindle
            funcConsume = JNI.createStaticMethod ("org/haxe/extension/iap/amazon/InAppPurchase", "consume", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
            #else
            funcConsume = JNI.createStaticMethod ("org/haxe/extension/iap/InAppPurchase", "consume", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
            #end

		}
		IAPHandler.lastPurchaseRequest = purchase.productID;
		funcConsume (purchase.originalJson, purchase.itemType, purchase.signature);

	}

	/**
	 * Queries the inventory. This will query all owned items from the server, as well as
	 * information on additional products, if specified.
	 *
	 * @param queryItemDetails if true, product details (price, description, etc) will be queried as well
	 *     as purchase information.
	 * @param moreItems additional PRODUCT IDs to query information on, regardless of ownership.
	 *     Ignored if null or if queryItemDetails is false.
	 *
	 * Related Events (IAPEvent):
	 * 		PURCHASE_QUERY_INVENTORY_COMPLETE: Fired when the query inventory attempt was successful.
	 * 			The inventory static property will be populated with new data.
	 * 		PURCHASE_QUERY_INVENTORY_FAILED: Fired when the query inventory attempt failed
	 */

	public static function queryInventory (queryItemDetails:Bool = false, moreItems:Array<String> = null):Void {
        trace("IAP:queryInventory");
		if (funcQueryInventory == null) {
            #if kindle
            funcQueryInventory = JNI.createStaticMethod ("org/haxe/extension/iap/amazon/InAppPurchase", "queryInventory", "(Z[Ljava/lang/String;)V");
            #else
            funcQueryInventory = JNI.createStaticMethod ("org/haxe/extension/iap/InAppPurchase", "queryInventory", "(Z[Ljava/lang/String;)V");
            #end
		}
		funcQueryInventory (queryItemDetails, moreItems);

	}

	// Getter & Setter Methods


	private static function get_available ():Bool {

		return IAPHandler.androidAvailable;

	}

	private static function get_manualTransactionMode ():Bool {

		return false;

	}

	private static function set_manualTransactionMode (val:Bool):Bool {

		return false;

	}

	// Event Dispatcher composition methods

	public static function addEventListener (type:String, listener:Dynamic, useCapture:Bool = false, priority:Int = 0, useWeakReference:Bool = false):Void {

		dispatcher.addEventListener (type, listener, useCapture, priority, useWeakReference);

	}

	public static function removeEventListener (type:String, listener:Dynamic, capture:Bool = false):Void {

		dispatcher.removeEventListener (type, listener, capture);

	}

	public static function dispatchEvent (event:Event):Bool {

		return dispatcher.dispatchEvent (event);

	}

	public static function hasEventListener (type:String):Bool {

		return dispatcher.hasEventListener (type);

	}

	// Native Methods
	private static var funcInit:Dynamic;
	private static var funcBuy:Dynamic;
	private static var funcConsume:Dynamic;
	private static var funcRestore:Dynamic;
	private static var funcQueryInventory:Dynamic;
	private static var funcTest:Dynamic;

}


#if (android && !display)

#if kindle

private class IAPHandler {

    public static var lastPurchaseRequest:String = "";
    public static var androidAvailable:Bool = true;

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function new () { }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onCanceledPurchase (productID:String):Void {
        trace("IAP:onCanceledPurchase - productID = " + productID);
        IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_CANCEL, productID));
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onFailedConsume (response:String):Void {
        trace("IAP:onFailedConsume - response = " + response);
        var productID:String = "";

        productID = lastPurchaseRequest; //temporal fix

        var dynResp:Dynamic = Json.parse(response);
        var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_CONSUME_FAILURE, productID);
        evt.productID = Reflect.field(Reflect.field(dynResp, "product"), "productId");
        evt.message = Reflect.field(Reflect.field(dynResp, "result"), "message");
        IAP.dispatcher.dispatchEvent (evt);
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onConsume (response:String):Void {
        trace("IAP:onConsume - response = " + response);
        var productID:String = "";

        productID = lastPurchaseRequest; //temporal fix

        var dynResp:Dynamic = Json.parse(response);
        var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_CONSUME_SUCCESS);
        evt.productID = Reflect.field(dynResp, "productId");
        IAP.dispatcher.dispatchEvent (evt);
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onFailedPurchase (response:String):Void {
        trace("IAP:onFailedPurchase - response = " + response);
        var productID:String = "";

        productID = lastPurchaseRequest; //temporal fix

        var dynResp:Dynamic = Json.parse(response);
        var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_FAILURE);
        if (Reflect.field(dynResp, "product") != null) evt.productID = Reflect.field(Reflect.field(dynResp, "product"), "productId");
        evt.message = Reflect.field(Reflect.field(dynResp, "result"), "message");
        IAP.dispatcher.dispatchEvent (evt);
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onPurchase (response:String):Void {
        trace("IAP:onPurchase - response = " + response);
        var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_SUCCESS);

        evt.purchase = new Purchase(response, "", "");
        evt.productID = evt.purchase.productID;
        IAP.inventory.purchaseMap.set(evt.purchase.productID, evt.purchase);

        IAP.dispatcher.dispatchEvent (evt);
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onQueryInventoryComplete (response:String):Void {
        trace("IAP:onQueryInventoryComplete - response = " + response);

        /*
        {
              "UNAVAILABLE_SKUS": "[product.vg_slots_21, product.vg_slots_4, product.vg_slots_6]",
              "requestStatus": "SUCCESSFUL",
              "requestId": "de04692d-7773-45e8-b68a-e6331631f98d",
              "productData": {
                "product.vg_slots_26": {
                  "title": "40 Gems",
                  "price": "$3",
                  "sku": "product.vg_slots_26",
                  "description": "40 Gems for use in Vegas World Slots",
                  "smallIconUrl": "https:\/\/s3-external-1.amazonaws.com\/com-amazon-mas-catalog\/M110Y1WIYDQV1V%2FM2JG7OU39NRGWW%2Fimages%2F_d2459a2f-6447-4e40-b126-4b7922235a8e_104bf7221b2ef67307968ae71a7b44aa",
                  "productType": "CONSUMABLE"
                }
              }
        }
         */

        if (response == "Failure") {
            androidAvailable = false;
            IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_QUERY_INVENTORY_FAILED));

        } else {
            trace("IAP:onQueryInventoryComplete: " + response);
            var dynResp:Dynamic = Json.parse(response);
            IAP.inventory = new Inventory(dynResp);

            var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_QUERY_INVENTORY_COMPLETE);
            evt.productsData = new Array<IAProduct>();

            var dynProductData:Dynamic = Reflect.field(dynResp, "productData");

            var prod:IAProduct;
            for (productName in Reflect.fields(dynProductData)) {
                var product = Reflect.field(dynProductData, productName);
                trace("product");
                trace(product);
                prod = { productID: Reflect.field(product, "sku") };
                prod.type = Reflect.field(product, "type");
                prod.localizedPrice = Reflect.field(product, "price");
                prod.localizedTitle = Reflect.field(product, "title");
                prod.localizedDescription = Reflect.field(product, "description");
                evt.productsData.push(prod);
            }

            IAP.dispatcher.dispatchEvent (evt);
            androidAvailable = true;
        }
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

    public function onStarted (response:String):Void {
        trace("IAP:onStarted - response " + response);
        if (response == "Success") {
            androidAvailable = true;
            IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_INIT));
        } else {
            androidAvailable = false;
            IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_INIT_FAILED));
        }
    }

///////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////

}
#else

private class IAPHandler {

	public static var lastPurchaseRequest:String = "";
	public static var androidAvailable:Bool = true;

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function new () { }

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onCanceledPurchase (productID:String):Void {
		IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_CANCEL, productID));
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onFailedConsume (response:String):Void {
		var productID:String = "";

		productID = lastPurchaseRequest; //temporal fix

		var dynResp:Dynamic = Json.parse(response);
		var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_CONSUME_FAILURE, productID);
		evt.productID = Reflect.field(Reflect.field(dynResp, "product"), "productId");
		evt.message = Reflect.field(Reflect.field(dynResp, "result"), "message");
		IAP.dispatcher.dispatchEvent (evt);
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onConsume (response:String):Void {
		var productID:String = "";

		productID = lastPurchaseRequest; //temporal fix

		var dynResp:Dynamic = Json.parse(response);
		var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_CONSUME_SUCCESS);
		evt.productID = Reflect.field(dynResp, "productId");
		IAP.dispatcher.dispatchEvent (evt);
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onFailedPurchase (response:String):Void {
		var productID:String = "";

		productID = lastPurchaseRequest; //temporal fix

		var dynResp:Dynamic = Json.parse(response);
		var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_FAILURE);
		if (Reflect.field(dynResp, "product") != null) evt.productID = Reflect.field(Reflect.field(dynResp, "product"), "productId");
		evt.message = Reflect.field(Reflect.field(dynResp, "result"), "message");
		IAP.dispatcher.dispatchEvent (evt);
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onPurchase (response:String, itemType:String, signature:String):Void {
		var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_SUCCESS);

		evt.purchase = new Purchase(response, itemType, signature);
		evt.productID = evt.purchase.productID;
		IAP.inventory.purchaseMap.set(evt.purchase.productID, evt.purchase);

		IAP.dispatcher.dispatchEvent (evt);
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onQueryInventoryComplete (response:String):Void {

		if (response == "Failure") {

			androidAvailable = false;
			IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_QUERY_INVENTORY_FAILED));

		} else {
            trace("IAP:onQueryInventoryComplete: " + response);
			var dynResp:Dynamic = Json.parse(response);
			IAP.inventory = new Inventory(dynResp);

			//trace("Parsed!: " + dynResp);
			var evt:IAPEvent = new IAPEvent (IAPEvent.PURCHASE_QUERY_INVENTORY_COMPLETE);
			evt.productsData = new Array<IAProduct>();

			var dynDescriptions:Array<Dynamic> = Reflect.field(dynResp, "descriptions");
			var dynItmValue:Dynamic;
			var prod:IAProduct;

			if (dynDescriptions != null) {
				for (dynItm in dynDescriptions) {
					dynItmValue = Reflect.field(dynItm, "value");
					prod = { productID: Reflect.field(dynItmValue, "productId") };
					prod.type = Reflect.field(dynItmValue, "type");
					prod.localizedPrice = Reflect.field(dynItmValue, "price");
					prod.priceAmountMicros = Reflect.field(dynItmValue, "price_amount_micros");
					prod.price = prod.priceAmountMicros / 1000 / 1000;
					prod.priceCurrencyCode = Reflect.field(dynItmValue, "price_currency_code");
					prod.localizedTitle = Reflect.field(dynItmValue, "title");
					prod.localizedDescription = Reflect.field(dynItmValue, "description");
					evt.productsData.push(prod);
				}
			}

			IAP.dispatcher.dispatchEvent (evt);
			androidAvailable = true;
		}
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

	public function onStarted (response:String):Void {
		if (response == "Success") {
			androidAvailable = true;
			IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_INIT));
		} else {
			androidAvailable = false;
			IAP.dispatcher.dispatchEvent (new IAPEvent (IAPEvent.PURCHASE_INIT_FAILED));
		}
	}

	///////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////////////////////

}

#end
#end
