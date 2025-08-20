package com.baseflow.permissionhandler;

import androidx.annotation.IntDef;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

public final class PermissionConstants {
    public static final String LOG_TAG = "PermissionHandler";

    private PermissionConstants() {}

    // Permission groups (only the ones referenced in plugin code are defined)
    public static final int PERMISSION_GROUP_UNKNOWN = 0;
    public static final int PERMISSION_GROUP_NOTIFICATION = 1;
    public static final int PERMISSION_GROUP_LOCATION = 2;
    public static final int PERMISSION_GROUP_LOCATION_ALWAYS = 3;
    public static final int PERMISSION_GROUP_LOCATION_WHEN_IN_USE = 4;
    public static final int PERMISSION_GROUP_BLUETOOTH = 5;
    public static final int PERMISSION_GROUP_BLUETOOTH_CONNECT = 6;
    public static final int PERMISSION_GROUP_BLUETOOTH_SCAN = 7;
    public static final int PERMISSION_GROUP_BLUETOOTH_ADVERTISE = 8;
    public static final int PERMISSION_GROUP_MICROPHONE = 9;
    public static final int PERMISSION_GROUP_SPEECH = 10;
    public static final int PERMISSION_GROUP_PHONE = 11;
    public static final int PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS = 12;
    public static final int PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE = 13;
    public static final int PERMISSION_GROUP_SYSTEM_ALERT_WINDOW = 14;
    public static final int PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES = 15;
    public static final int PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY = 16;
    public static final int PERMISSION_GROUP_SCHEDULE_EXACT_ALARM = 17;

    // Permission statuses
    public static final int PERMISSION_STATUS_GRANTED = 0;
    public static final int PERMISSION_STATUS_DENIED = 1;
    public static final int PERMISSION_STATUS_RESTRICTED = 2;

    // Service statuses
    public static final int SERVICE_STATUS_ENABLED = 0;
    public static final int SERVICE_STATUS_DISABLED = 1;
    public static final int SERVICE_STATUS_NOT_APPLICABLE = 2;

    // Request codes
    public static final int PERMISSION_CODE = 200;
    public static final int PERMISSION_CODE_IGNORE_BATTERY_OPTIMIZATIONS = 201;
    public static final int PERMISSION_CODE_MANAGE_EXTERNAL_STORAGE = 202;
    public static final int PERMISSION_CODE_SYSTEM_ALERT_WINDOW = 203;
    public static final int PERMISSION_CODE_REQUEST_INSTALL_PACKAGES = 204;
    public static final int PERMISSION_CODE_ACCESS_NOTIFICATION_POLICY = 205;
    public static final int PERMISSION_CODE_SCHEDULE_EXACT_ALARM = 206;

    // IntDef annotations
    @IntDef({
        PERMISSION_GROUP_UNKNOWN,
        PERMISSION_GROUP_NOTIFICATION,
        PERMISSION_GROUP_LOCATION,
        PERMISSION_GROUP_LOCATION_ALWAYS,
        PERMISSION_GROUP_LOCATION_WHEN_IN_USE,
        PERMISSION_GROUP_BLUETOOTH,
        PERMISSION_GROUP_BLUETOOTH_CONNECT,
        PERMISSION_GROUP_BLUETOOTH_SCAN,
        PERMISSION_GROUP_BLUETOOTH_ADVERTISE,
        PERMISSION_GROUP_MICROPHONE,
        PERMISSION_GROUP_SPEECH,
        PERMISSION_GROUP_PHONE,
        PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS,
        PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE,
        PERMISSION_GROUP_SYSTEM_ALERT_WINDOW,
        PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES,
        PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY,
        PERMISSION_GROUP_SCHEDULE_EXACT_ALARM
    })
    @Retention(RetentionPolicy.SOURCE)
    public @interface PermissionGroup {}

    @IntDef({
        PERMISSION_STATUS_GRANTED,
        PERMISSION_STATUS_DENIED,
        PERMISSION_STATUS_RESTRICTED
    })
    @Retention(RetentionPolicy.SOURCE)
    public @interface PermissionStatus {}

    @IntDef({
        SERVICE_STATUS_ENABLED,
        SERVICE_STATUS_DISABLED,
        SERVICE_STATUS_NOT_APPLICABLE
    })
    @Retention(RetentionPolicy.SOURCE)
    public @interface ServiceStatus {}
}
