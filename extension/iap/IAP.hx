package extension.iap;

typedef IAProduct = extension.iap.TIAProduct;

#if ios

typedef IAP = extension.iap.ios.IAP;

#elseif android

typedef IAP = extension.iap.android.IAP;

#elseif blackberry

typedef IAP = extension.iap.blackberry.IAP;

#elseif (html5 && uwa)

typedef IAP = extension.iap.uwajs.IAP;

#else

typedef IAP = extension.iap.fallback.IAP;

#end
