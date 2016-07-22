package org.haxe.extension.iap.amazon;

import java.util.Arrays;
import java.util.List;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import org.json.JSONObject;
import org.json.JSONException;

import com.amazon.device.iap.PurchasingService;
import com.amazon.device.iap.PurchasingListener;
import com.amazon.device.iap.model.RequestId;
import com.amazon.device.iap.model.FulfillmentResult;
import com.amazon.device.iap.model.Product;
import com.amazon.device.iap.model.Receipt;
import com.amazon.device.iap.model.UserData;
import com.amazon.device.iap.model.UserDataResponse;
import com.amazon.device.iap.model.ProductDataResponse;
import com.amazon.device.iap.model.PurchaseUpdatesResponse;
import com.amazon.device.iap.model.PurchaseResponse;

import java.util.HashSet;
import java.util.Set;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.view.View.OnClickListener;
import android.widget.Button;
import android.widget.ImageView;
import org.haxe.extension.iap.util.*;
import org.haxe.extension.Extension;
import org.haxe.lime.HaxeObject;

import org.json.JSONException;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

public class InAppPurchase extends Extension {
    private static final String TAG = "IAP";

	private static HaxeObject callback = null;
    private static String publicKey = "";

    public static void buy (final String productID, final String devPayload) {
		Extension.mainActivity.runOnUiThread(new Runnable() {
				public void run() {
					try {
                        final RequestId requestId = PurchasingService.purchase(productID);
                        Log.d(TAG, "buy: requestId (" + requestId + ")");
					} catch (Exception exception) {
						Log.e(TAG, "Failed to launch purchase flow.", exception);
					}
				}
			});
	}
	
	public static void consume (final String purchaseJson, final String itemType, final String signature) 
	{
        PurchasingService.getPurchaseUpdates(false);

        Extension.callbackHandler.post (new Runnable ()
        {
            @Override public void run ()
            {
                InAppPurchase.callback.call ("onConsume", new Object[] { purchaseJson });
            }
        });
	}
	
	public static void queryInventory (final boolean querySkuDetails, String[] moreSkusArr) {

        Log.d(TAG, "queryInventory: call getProductData for skus");
        final Set<String> productSkus = new HashSet<String>();
        for (final String sku : moreSkusArr) {
            Log.d(TAG, "queryInventory: call getProductData for sku: " + sku);
            productSkus.add(sku);
        }

		Extension.mainActivity.runOnUiThread(new Runnable() {
			public void run() {
				try {
                    Log.d(TAG, "queryInventory: calling getProductData for " + productSkus.size() + " products");
                    PurchasingService.getProductData(productSkus);
				} catch(Exception e) {
					Log.d(TAG, e.getMessage());
				}
			}
		});
	}
	
	public static String getPublicKey () {
		
		return publicKey;
		
	}
	
	
	public static void initialize (String publicKey, HaxeObject callback) {
		
		Log.i (TAG, "Initializing billing service");
		
		InAppPurchase.publicKey = publicKey; // not used
		InAppPurchase.callback = callback;

        Log.d(TAG, "initialize: registering PurchasingListener");
        PurchasingService.registerListener(Extension.mainContext, mPurchasingListener);
        Log.d(TAG, "IS_SANDBOX_MODE:" + PurchasingService.IS_SANDBOX_MODE);

        Log.d(TAG, "onResume: call getUserData");
        PurchasingService.getUserData();
        Log.d(TAG, "onResume: getPurchaseUpdates");
        PurchasingService.getPurchaseUpdates(false);


        Extension.callbackHandler.post (new Runnable () {

            @Override public void run () {

                InAppPurchase.callback.call ("onStarted", new Object[] { "Success" });

            }

        });
	}
	
	
	public static void setPublicKey (String s) {
		
		publicKey = s;
		
	}

    static PurchasingListener mPurchasingListener = new PurchasingListener() {
        /**
         * This is the callback for {@link PurchasingService#getUserData}. For
         * successful case, get the current user from {@link UserDataResponse}.
         *
         * @param response
         */
        @Override
        public void onUserDataResponse(final UserDataResponse response) {
            Log.d(TAG, "onGetUserDataResponse: requestId (" + response.getRequestId()
                    + ") userIdRequestStatus: "
                    + response.getRequestStatus()
                    + ")");

            final UserDataResponse.RequestStatus status = response.getRequestStatus();
            switch (status) {
                case SUCCESSFUL:
                    Log.d(TAG, "onUserDataResponse: get user id (" + response.getUserData().getUserId()
                            + ", marketplace ("
                            + response.getUserData().getMarketplace()
                            + ") ");
                    break;

                case FAILED:
                case NOT_SUPPORTED:
                default:
                    Log.d(TAG, "onUserDataResponse failed, status code is " + status);
                    break;
            }
        }

        /**
         * This is the callback for {@link PurchasingService#getProductData}.
         */
        @Override
        public void onProductDataResponse(final ProductDataResponse response) {
            final ProductDataResponse.RequestStatus status = response.getRequestStatus();
            Log.d(TAG, "onProductDataResponse: RequestStatus (" + status + ")");



            switch (status) {
                case SUCCESSFUL:
                    Log.d(TAG, "onProductDataResponse: successful.  The item data map in this response includes the valid SKUs");
                    final Set<String> unavailableSkus = response.getUnavailableSkus();
                    Log.d(TAG, "onProductDataResponse: " + unavailableSkus.size() + " unavailable skus");

                    Extension.callbackHandler.post (new Runnable ()
                    {
                        @Override public void run ()
                        {

                            try {
                                JSONObject productJSON = response.toJSON();
                                InAppPurchase.callback.call ("onQueryInventoryComplete", new Object[] { productJSON.toString() });
                            }
                            catch (JSONException je) {
                                InAppPurchase.callback.call ("onQueryInventoryComplete", new Object[] { "Failure" });
                            }
                        }
                    });

                    break;
                case FAILED:
                case NOT_SUPPORTED:
                default:
                    Log.d(TAG, "onProductDataResponse: failed, should retry request");

                    Extension.callbackHandler.post (new Runnable ()
                    {
                        @Override public void run ()
                        {

                            InAppPurchase.callback.call ("onQueryInventoryComplete", new Object[] { "Failure" });


                        }
                    });
                    break;
            }
        }

        /**
         * This is the callback for {@link PurchasingService#getPurchaseUpdates}.
         *
         * We will receive Consumable receipts from this callback if the consumable
         * receipts are not marked as "FULFILLED" in Amazon Appstore.
         *
         */
        @Override
        public void onPurchaseUpdatesResponse(final PurchaseUpdatesResponse response) {
            Log.d(TAG, "onPurchaseUpdatesResponse: requestId (" + response.getRequestId()
                    + ") purchaseUpdatesResponseStatus ("
                    + response.getRequestStatus()
                    + ") userId ("
                    + response.getUserData().getUserId()
                    + ")");
            final PurchaseUpdatesResponse.RequestStatus status = response.getRequestStatus();
            switch (status) {
                case SUCCESSFUL:

                    for (final Receipt receipt : response.getReceipts()) {
                        Log.d(TAG, "onPurchaseUpdatesResponse: need to handle receipt" + receipt.toString());

                        PurchasingService.notifyFulfillment(receipt.getReceiptId(), FulfillmentResult.FULFILLED);
                    }
                    if (response.hasMore()) {
                        PurchasingService.getPurchaseUpdates(false);
                    }

                    break;
                case FAILED:
                case NOT_SUPPORTED:
                default:
                    Log.d(TAG, "onProductDataResponse: failed, should retry request");
                    break;
            }

        }

        /**
         * This is the callback for {@link PurchasingService#purchase}. For each
         * time the application sends a purchase request
         * {@link PurchasingService#purchase}, Amazon Appstore will call this
         * callback when the purchase request is completed. If the RequestStatus is
         * Successful or AlreadyPurchased then application needs to call
         * handleReceipt to handle the purchase
         * fulfillment. If the RequestStatus is INVALID_SKU, NOT_SUPPORTED, or
         * FAILED, notify corresponding method.
         */
        @Override
        public void onPurchaseResponse(final PurchaseResponse response) {
            final String requestId = response.getRequestId().toString();
            final String userId = response.getUserData().getUserId();
            final PurchaseResponse.RequestStatus status = response.getRequestStatus();
            final Receipt receipt = response.getReceipt();
            final String productId = receipt.getSku();

            Log.d(TAG, "onPurchaseResponse: requestId (" + requestId
                    + ") userId ("
                    + userId
                    + ") purchaseRequestStatus ("
                    + status
                    + ")");

            switch (status) {
                case SUCCESSFUL:

                    Log.d(TAG, "onPurchaseResponse: receipt json:" + receipt.toString());

                    Extension.callbackHandler.post (new Runnable ()
                    {
                        @Override public void run ()
                        {
                            JSONObject callbackJSON = new JSONObject();

                            try {
                                callbackJSON.put("productId", receipt.getSku());
                                callbackJSON.put("userId", userId);
                                callbackJSON.put("receiptId", receipt.getReceiptId());
                                InAppPurchase.callback.call("onPurchase", new Object[]{callbackJSON.toString()});
                            }
                            catch (JSONException je) {
                                InAppPurchase.callback.call ("onFailedPurchase", new Object[] { je.toString() });
                            }
                        }
                    });
                    break;
                case ALREADY_PURCHASED:
                    Log.d(TAG, "onPurchaseResponse: already purchased, should never get here for a consumable.");
                    // This is not applicable for consumable item. It is only
                    // application for entitlement and subscription.
                    // check related samples for more details.
                    break;
                case INVALID_SKU:
                    Log.d(TAG,
                            "onPurchaseResponse: invalid SKU!  onProductDataResponse should have disabled buy button already.");
                    Extension.callbackHandler.post (new Runnable ()
                    {
                        @Override public void run ()
                        {
                            InAppPurchase.callback.call ("onFailedPurchase", new Object[] { ("{\"result\":" + response.toString() + ", \"product\":" + ((receipt != null)? receipt.toString() : "null") + "}") });
                        }
                    });
                    break;
                case FAILED:
                case NOT_SUPPORTED:
                default:
                    Log.d(TAG, "onPurchaseResponse: failed so remove purchase request from local storage");

                    Extension.callbackHandler.post (new Runnable ()
                    {
                        @Override public void run ()
                        {
                            InAppPurchase.callback.call ("onFailedPurchase", new Object[] { ("{\"result\":" + response.toString() + ", \"product\":" + ((receipt != null)? receipt.toString() : "null") + "}") });
                        }
                    });
                    break;
            }

        }
    };
}
