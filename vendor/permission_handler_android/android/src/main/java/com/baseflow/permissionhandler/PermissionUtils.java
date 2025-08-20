package com.baseflow.permissionhandler;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.ActivityCompat;

import java.util.ArrayList;
import java.util.List;

public final class PermissionUtils {
    private PermissionUtils() { }

    public static int parseManifestName(String permissionName) {
        if (permissionName == null) return PermissionConstants.PERMISSION_GROUP_UNKNOWN;

        switch (permissionName) {
            case Manifest.permission.POST_NOTIFICATIONS:
                return PermissionConstants.PERMISSION_GROUP_NOTIFICATION;
            case Manifest.permission.ACCESS_FINE_LOCATION:
            case Manifest.permission.ACCESS_COARSE_LOCATION:
                return PermissionConstants.PERMISSION_GROUP_LOCATION;
            case Manifest.permission.ACCESS_BACKGROUND_LOCATION:
                return PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS;
            case Manifest.permission.RECORD_AUDIO:
                return PermissionConstants.PERMISSION_GROUP_MICROPHONE;
            case Manifest.permission.BLUETOOTH_SCAN:
            case Manifest.permission.BLUETOOTH_CONNECT:
            case Manifest.permission.BLUETOOTH_ADVERTISE:
            case Manifest.permission.BLUETOOTH:
                return PermissionConstants.PERMISSION_GROUP_BLUETOOTH;
            case Manifest.permission.CALL_PHONE:
            case Manifest.permission.READ_PHONE_STATE:
                return PermissionConstants.PERMISSION_GROUP_PHONE;
            default:
                return PermissionConstants.PERMISSION_GROUP_UNKNOWN;
        }
    }

    public static int toPermissionStatus(Context context, String permissionName, int grantResult) {
        return grantResult == PackageManager.PERMISSION_GRANTED
            ? PermissionConstants.PERMISSION_STATUS_GRANTED
            : PermissionConstants.PERMISSION_STATUS_DENIED;
    }

    public static void updatePermissionShouldShowStatus(Activity activity, int permission) {
        if (activity == null) return;
        List<String> names = getManifestNames(activity, permission);
        if (names == null || names.isEmpty()) return;
        // Query shouldShowRequestPermissionRationale for the first manifest permission.
        boolean should = ActivityCompat.shouldShowRequestPermissionRationale(activity, names.get(0));
        // This simple implementation does not persist the value; it's a best-effort no-op to satisfy callers.
    }

    public static List<String> getManifestNames(Context context, int permission) {
        List<String> names = new ArrayList<>();

        switch (permission) {
            case PermissionConstants.PERMISSION_GROUP_NOTIFICATION:
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    names.add(Manifest.permission.POST_NOTIFICATIONS);
                    return names;
                }
                return null;
            case PermissionConstants.PERMISSION_GROUP_LOCATION:
            case PermissionConstants.PERMISSION_GROUP_LOCATION_WHEN_IN_USE:
                names.add(Manifest.permission.ACCESS_FINE_LOCATION);
                names.add(Manifest.permission.ACCESS_COARSE_LOCATION);
                return names;
            case PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS:
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    names.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION);
                }
                return names;
            case PermissionConstants.PERMISSION_GROUP_MICROPHONE:
                names.add(Manifest.permission.RECORD_AUDIO);
                return names;
            case PermissionConstants.PERMISSION_GROUP_BLUETOOTH:
            case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_CONNECT:
            case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_SCAN:
            case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_ADVERTISE:
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    names.add(Manifest.permission.BLUETOOTH_CONNECT);
                    names.add(Manifest.permission.BLUETOOTH_SCAN);
                    names.add(Manifest.permission.BLUETOOTH_ADVERTISE);
                    return names;
                }
                // On older Android versions, Bluetooth permissions are either normal permissions or not required at runtime.
                return null;
            case PermissionConstants.PERMISSION_GROUP_PHONE:
                names.add(Manifest.permission.CALL_PHONE);
                names.add(Manifest.permission.READ_PHONE_STATE);
                return names;
            case PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS:
            case PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE:
            case PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW:
            case PermissionConstants.PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES:
            case PermissionConstants.PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY:
            case PermissionConstants.PERMISSION_GROUP_SCHEDULE_EXACT_ALARM:
                // These are special permissions handled via Settings intents rather than runtime permissions.
                return null;
            default:
                return null;
        }
    }
}
