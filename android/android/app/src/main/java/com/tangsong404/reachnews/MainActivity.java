package com.tangsong404.reachnews;

import android.os.Bundle;
import android.view.View;
import android.webkit.WebView;
import androidx.activity.EdgeToEdge;
import androidx.annotation.NonNull;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsAnimationCompat;
import androidx.core.view.WindowInsetsCompat;
import com.getcapacitor.BridgeActivity;
import java.util.List;

// 与可及清单相同：画面铺到状态栏和手势条后面，页面用 --safe-area-inset-* 自己留白；
// 键盘动画的每一帧把「键盘露出多高」推给页面（window.__ime），追问输入栏逐帧跟随。
public class MainActivity extends BridgeActivity {
    private boolean imeAnimating = false;
    private int lastSent = -1;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        EdgeToEdge.enable(this);
        trackKeyboard();
    }

    private void trackKeyboard() {
        View root = getWindow().getDecorView();
        ViewCompat.setWindowInsetsAnimationCallback(
            root,
            new WindowInsetsAnimationCompat.Callback(WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_STOP) {
                @Override
                public void onPrepare(@NonNull WindowInsetsAnimationCompat animation) {
                    if (isIme(animation)) imeAnimating = true;
                }

                @NonNull
                @Override
                public WindowInsetsAnimationCompat.BoundsCompat onStart(
                    @NonNull WindowInsetsAnimationCompat animation,
                    @NonNull WindowInsetsAnimationCompat.BoundsCompat bounds
                ) {
                    return bounds;
                }

                @NonNull
                @Override
                public WindowInsetsCompat onProgress(
                    @NonNull WindowInsetsCompat insets,
                    @NonNull List<WindowInsetsAnimationCompat> running
                ) {
                    send(insets, true);
                    return insets;
                }

                @Override
                public void onEnd(@NonNull WindowInsetsAnimationCompat animation) {
                    if (!isIme(animation)) return;
                    imeAnimating = false;
                    WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(root);
                    if (insets != null) send(insets, false);
                }
            }
        );
        WebView web = getBridge().getWebView();
        ViewCompat.setOnApplyWindowInsetsListener(web, (v, insets) -> {
            if (!imeAnimating) send(insets, false);
            return ViewCompat.onApplyWindowInsets(v, insets);
        });
    }

    private static boolean isIme(WindowInsetsAnimationCompat a) {
        return (a.getTypeMask() & WindowInsetsCompat.Type.ime()) != 0;
    }

    // 只算手势条以上的部分，单位换成 CSS 像素
    private void send(WindowInsetsCompat insets, boolean animating) {
        Insets ime = insets.getInsets(WindowInsetsCompat.Type.ime());
        Insets nav = insets.getInsets(WindowInsetsCompat.Type.navigationBars());
        float density = getResources().getDisplayMetrics().density;
        int h = Math.round(Math.max(0, ime.bottom - nav.bottom) / density);
        if (h == lastSent && animating) return;
        lastSent = h;
        WebView web = getBridge().getWebView();
        if (web != null) web.evaluateJavascript("window.__ime&&__ime(" + h + "," + animating + ")", null);
    }
}
