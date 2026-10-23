package com.shapematch.meter;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.BlackLevelPattern;
import android.hardware.camera2.params.ColorSpaceTransform;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.speech.tts.TextToSpeech;
import android.util.Range;
import android.util.Size;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

/**
 * Shape Match Meter: a light meter for Shape Match's screen calibration that
 * reads the camera's raw sensor data, as the calibration article asks, rather
 * than the processed picture a web page gets. Raw data is the light itself,
 * linear, before the phone's tone curve, sharpening, color boosting and white
 * balance, so the game can measure solid patches directly (see
 * scripts/raw_calibration.gd).
 *
 * It finds the game by scanning the same QR code the game shows for the web
 * page (QrReader), or opens straight from that page with
 * shapematch-meter://connect?u=address&amp;s=session. Then it posts what it
 * sees in the middle of the picture to the game, and the game answers with
 * the next patch and what it is, which the meter shows and says aloud.
 * Exposure, ISO and focus are fixed by hand: exposure so white comes out
 * bright but not clipped, and focus at infinity, so a screen held close is
 * blurred.
 */
public class MeterActivity extends Activity {
	private static final int ASK_CAMERA = 1;
	private static final int VERSION = 5;  // as android:versionCode; the game says which it expects
	// Radii as shares of half the sensor's shorter side, as in phone.html: the
	// disc is measured inside INNER, the screen's background between OUTER_FROM
	// and OUTER_TO, and the disc's edge belongs between EDGE_NEAR and EDGE_FAR.
	private static final double INNER = 0.25;
	private static final double OUTER_FROM = 0.75;
	private static final double OUTER_TO = 0.95;
	private static final double EDGE_NEAR = 0.35;
	private static final double EDGE_FAR = 0.65;
	private static final int BINS = 20;  // rings the brightness is profiled in, to find the disc's edge
	private static final int SAMPLES = 700;  // 2x2 filter blocks read each way across the measured square
	private static final int THUMB = 72;  // pixels each way of the picture shown while lining up
	private static final double CLIPPED = 0.98;  // share of the white level at which a pixel counts as clipped
	private static final double CLIP_LIMIT = 0.001;  // share of clipped pixels that makes a reading too bright
	private static final int MAX_FRAMES = 12;  // raw pictures a reading may take while they disagree
	private static final double SPREAD_LIMIT = 0.02;  // how far apart (over their average) pictures may be before more are taken
	/** Exposure times to choose from, in ns: whole periods of 50 and 60 Hz flicker where they are long enough. */
	private static final long[] TIMES = {
		50_000_000L, 33_333_333L, 20_000_000L, 16_666_667L, 10_000_000L, 8_333_333L, 4_000_000L,
		2_000_000L, 1_000_000L, 500_000L, 250_000L, 125_000L, 62_500L, 31_250L,
	};
	private static final int BASE_ISO = 100;  // ISO used, where the camera allows; exposure time does the rest
	private static final String[] STEPS = {"Scan", "Line up", "Measure", "Done"};

	/** Where the meter is: each shows its own things in the one layout. */
	private enum Mode { SCAN, CONNECTING, LINE_UP, MEASURE, DONE, PROBLEM }

	private volatile Mode mode = Mode.SCAN;
	private String base;  // the game's address, https://host:port
	private String session;
	private volatile boolean connected;

	// The screen
	private LinearLayout stepper;
	private TextureView view;
	private ImageView picture;  // what the sensor sees, with the rings the disc's edge belongs between
	private Look.Viewfinder finder;
	private Look.Swatch swatch;
	private TextView title, body, primary, secondary, speaker;
	private LinearLayout chips;
	private HorizontalScrollView chipScroll;
	private Look.Bar bar;
	private Runnable primaryAction, secondaryAction;
	private int shownStage = -1;
	private long measureStarted;

	// Speaking
	private TextToSpeech voice;
	private boolean voiceReady;
	private SharedPreferences settings;

	// The camera
	private HandlerThread cameraThread, scanThread;
	private Handler cameraHandler, scanHandler;
	private CameraManager manager;
	private String cameraId;
	private CameraDevice camera;
	private CameraCaptureSession capture;
	private CameraCharacteristics characteristics;
	private ImageReader raw, scanFrames;
	private Surface preview;
	private Size previewSize;
	private volatile boolean decoding;
	private long minFrame;  // ns, the raw stream's shortest frame
	private Range<Long> timeRange;
	private Range<Integer> isoRange;
	private int timeIndex = 3;  // into TIMES
	private int iso;
	private int shownTime = -1, shownIso = -1;  // the settings the preview runs at, so measuring restarts it only on a change
	private int whiteLevel;
	private BlackLevelPattern blackLevel;
	private int cfa;  // SENSOR_INFO_COLOR_FILTER_ARRANGEMENT
	private boolean collecting;
	private final LinkedBlockingQueue<Image> images = new LinkedBlockingQueue<>();
	private volatile boolean measuring;
	private boolean canMeasure;  // the camera gives raw data under manual control
	private boolean stuck;  // can't get any darker

	@Override
	protected void onCreate(Bundle state) {
		super.onCreate(state);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		getWindow().setStatusBarColor(Color.rgb(207, 234, 255));
		getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
		settings = getSharedPreferences("meter", MODE_PRIVATE);
		buildUi();
		voice = new TextToSpeech(this, status -> {
			voiceReady = status == TextToSpeech.SUCCESS;
			if (voiceReady) voice.setLanguage(Locale.US);
		});
		readIntent(getIntent());
		cameraThread = new HandlerThread("camera");
		cameraThread.start();
		cameraHandler = new Handler(cameraThread.getLooper());
		scanThread = new HandlerThread("scan");
		scanThread.start();
		scanHandler = new Handler(scanThread.getLooper());
		show(base == null ? Mode.SCAN : Mode.CONNECTING);
		if (getIntent().hasExtra("preview")) {
			preview(getIntent().getStringExtra("preview"));
			return;
		}
		if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
			requestPermissions(new String[] {Manifest.permission.CAMERA}, ASK_CAMERA);
		} else {
			waitForPreview();
		}
	}

	@Override
	protected void onNewIntent(Intent intent) {
		super.onNewIntent(intent);
		readIntent(intent);
		if (base != null && camera != null && !measuring) connect();
	}

	@Override
	protected void onDestroy() {
		super.onDestroy();
		connected = false;
		if (voice != null) voice.shutdown();
		if (capture != null) capture.close();
		if (camera != null) camera.close();
		if (raw != null) raw.close();
		if (scanFrames != null) scanFrames.close();
		cameraThread.quitSafely();
		scanThread.quitSafely();
	}

	@Override
	public void onRequestPermissionsResult(int code, String[] permissions, int[] results) {
		if (code == ASK_CAMERA && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
			waitForPreview();
		} else {
			problem("The meter needs the camera", "It measures the screen with it, and reads the code. Allow the camera in the phone's settings, then open the meter again.", null, null);
		}
	}

	// ---------- Screen ----------

	private void buildUi() {
		int pad = dp(18);
		LinearLayout page = new LinearLayout(this);
		page.setOrientation(LinearLayout.VERTICAL);
		page.setPadding(pad, dp(14), pad, pad);
		page.setBackground(Look.sky());

		// The name, the game's shapes, and the voice switch.
		LinearLayout header = new LinearLayout(this);
		header.setGravity(Gravity.CENTER_VERTICAL);
		header.addView(new Look.Logo(this), new LinearLayout.LayoutParams(dp(76), dp(34)));
		TextView name = Look.text(this, "Shape Match Meter", 22, true, Look.INK);
		LinearLayout.LayoutParams grow = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
		grow.leftMargin = dp(8);
		header.addView(name, grow);
		speaker = Look.text(this, "", 20, false, Look.INK);
		speaker.setGravity(Gravity.CENTER);
		speaker.setBackground(Look.round(this, Color.WHITE, 22, 2));
		speaker.setOnClickListener(v -> {
			boolean quiet = !settings.getBoolean("quiet", false);
			settings.edit().putBoolean("quiet", quiet).apply();
			if (quiet && voice != null) voice.stop();
			showSpeaker();
		});
		header.addView(speaker, new LinearLayout.LayoutParams(dp(44), dp(44)));
		showSpeaker();
		page.addView(header);

		// Where the meter is: Scan, Line up, Measure, Done.
		stepper = new LinearLayout(this);
		stepper.setGravity(Gravity.CENTER);
		LinearLayout.LayoutParams stepperAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		stepperAt.topMargin = dp(10);
		page.addView(stepper, stepperAt);

		// The camera card: the preview when scanning, the raw picture when
		// lining up, the color on screen when measuring.
		FrameLayout holder = new FrameLayout(this);
		LinearLayout.LayoutParams holderAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
		holderAt.topMargin = dp(14);
		holderAt.bottomMargin = dp(14);
		page.addView(holder, holderAt);
		Look.Aspect card = new Look.Aspect(this, 4f / 3f);
		card.setBackground(Look.round(this, Look.SCREEN, 26, 3));
		card.setElevation(dp(6));
		Look.clipRound(card, 26);
		holder.addView(card, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER));
		view = new TextureView(this);
		card.addView(view, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
		picture = new ImageView(this);
		picture.setScaleType(ImageView.ScaleType.CENTER_CROP);
		picture.setBackgroundColor(Look.SCREEN);
		card.addView(picture, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
		swatch = new Look.Swatch(this);
		card.addView(swatch, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
		finder = new Look.Viewfinder(this);
		card.addView(finder, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

		// What is happening, and what to do, on a paper sheet.
		LinearLayout sheet = new LinearLayout(this);
		sheet.setOrientation(LinearLayout.VERTICAL);
		sheet.setBackground(Look.round(this, Look.PAPER, 26, 2.5f));
		sheet.setElevation(dp(4));
		sheet.setPadding(dp(18), dp(16), dp(18), dp(16));
		page.addView(sheet, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
		title = Look.text(this, "", 24, true, Look.INK);
		sheet.addView(title);
		body = Look.text(this, "", 16, false, Look.INK_SOFT);
		LinearLayout.LayoutParams bodyAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		bodyAt.topMargin = dp(4);
		sheet.addView(body, bodyAt);

		chipScroll = new HorizontalScrollView(this);
		chipScroll.setHorizontalScrollBarEnabled(false);
		chips = new LinearLayout(this);
		chipScroll.addView(chips);
		LinearLayout.LayoutParams chipsAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		chipsAt.topMargin = dp(12);
		sheet.addView(chipScroll, chipsAt);
		bar = new Look.Bar(this);
		LinearLayout.LayoutParams barAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(16));
		barAt.topMargin = dp(10);
		sheet.addView(bar, barAt);

		primary = Look.button(this, "", Look.GO);
		primary.setOnClickListener(v -> {
			if (primaryAction != null) primaryAction.run();
		});
		LinearLayout.LayoutParams primaryAt = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		primaryAt.topMargin = dp(14);
		sheet.addView(primary, primaryAt);
		secondary = Look.text(this, "", 15, true, Color.rgb(31, 95, 168));
		secondary.setGravity(Gravity.CENTER);
		secondary.setPadding(0, dp(10), 0, 0);
		secondary.setOnClickListener(v -> {
			if (secondaryAction != null) secondaryAction.run();
		});
		sheet.addView(secondary, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
		// Clear of the status and navigation bars, which Android 15 draws over apps.
		page.setOnApplyWindowInsetsListener((v, insets) -> {
			v.setPadding(pad, dp(10) + insets.getSystemWindowInsetTop(), pad, pad + insets.getSystemWindowInsetBottom());
			return insets.consumeSystemWindowInsets();
		});
		setContentView(page);
	}

	private void showSpeaker() {
		speaker.setText(settings.getBoolean("quiet", false) ? "🔇" : "🔊");
	}

	/** Switches what the layout shows to mode's things, with its words. */
	private void show(Mode next) {
		mode = next;
		runOnUiThread(() -> {
			int step = next == Mode.SCAN || next == Mode.CONNECTING ? 0 : next == Mode.LINE_UP ? 1 : next == Mode.MEASURE ? 2 : next == Mode.DONE ? STEPS.length : -1;
			if (step >= 0) {
				stepper.removeAllViews();
				for (int i = 0; i < STEPS.length; i++) {
					TextView chip = Look.chip(this, STEPS[i], i < step ? -1 : i == step ? 0 : 1);
					LinearLayout.LayoutParams at = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
					at.leftMargin = at.rightMargin = dp(3);
					stepper.addView(chip, at);
				}
			}
			finder.setVisibility(next == Mode.SCAN ? View.VISIBLE : View.GONE);
			picture.setVisibility(next == Mode.LINE_UP ? View.VISIBLE : View.GONE);
			swatch.setVisibility(next == Mode.MEASURE || next == Mode.DONE ? View.VISIBLE : View.GONE);
			if (next == Mode.DONE) swatch.done();
			chipScroll.setVisibility(next == Mode.MEASURE ? View.VISIBLE : View.GONE);
			bar.setVisibility(next == Mode.MEASURE ? View.VISIBLE : View.GONE);
			switch (next) {
				case SCAN:
					words("Scan the code on the computer", "In Shape Match, open Grown-up settings, then Calibration, then With a phone camera. Point this camera at the code that appears.");
					buttons(null, null, null, null);
					break;
				case CONNECTING:
					words("Connecting…", "Finding Shape Match on this Wi-Fi.");
					buttons(null, null, "Scan a different code", this::rescan);
					break;
				case LINE_UP:
					buttons("Start measuring", this::startMeasuring, null, null);
					break;
				case MEASURE:
					buttons(null, null, null, null);
					break;
				case DONE:
					words("All done!", "The result is on the computer. To measure again, tap Try again there, then Measure again here.");
					buttons("Measure again", () -> show(Mode.LINE_UP), null, null);
					break;
				default:
					break;
			}
		});
	}

	private void words(String heading, String detail) {
		runOnUiThread(() -> {
			title.setText(heading);
			body.setText(detail);
		});
	}

	private void buttons(String main, Runnable mainAction, String other, Runnable otherAction) {
		runOnUiThread(() -> {
			primary.setVisibility(main == null ? View.GONE : View.VISIBLE);
			primary.setText(main == null ? "" : main);
			primaryAction = mainAction;
			secondary.setVisibility(other == null ? View.GONE : View.VISIBLE);
			secondary.setText(other == null ? "" : other);
			secondaryAction = otherAction;
		});
	}

	/** Something went wrong: says what, with what can be done about it. */
	private void problem(String heading, String detail, String action, Runnable run) {
		mode = Mode.PROBLEM;
		runOnUiThread(() -> {
			finder.setVisibility(View.GONE);
			picture.setVisibility(View.GONE);
			swatch.setVisibility(View.VISIBLE);
			swatch.problem();
			chipScroll.setVisibility(View.GONE);
			bar.setVisibility(View.GONE);
			words(heading, detail);
			buttons(action, run, base != null ? "Scan a different code" : null, base != null ? this::rescan : null);
		});
		speak(heading);
	}

	/**
	 * Shows one screen with made-up readings, to see how it looks without a
	 * computer or a raw camera: adb shell am start -n
	 * com.shapematch.meter/.MeterActivity --es preview line_up|measure|done|problem
	 */
	private void preview(String which) {
		try {
			if ("line_up".equals(which)) {
				show(Mode.LINE_UP);
				words("Center the circle", "On the computer, drag the dark circle a little, until it sits in the middle of the picture above.");
				Bitmap fake = Bitmap.createBitmap(480, 480, Bitmap.Config.ARGB_8888);
				Canvas canvas = new Canvas(fake);
				canvas.drawColor(Color.rgb(200, 200, 200));
				android.graphics.Paint dark = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
				dark.setColor(Color.rgb(40, 40, 40));
				canvas.drawCircle(270, 230, 120, dark);
				Look.rings(canvas, 480, EDGE_NEAR, EDGE_FAR, false, this);
				picture.setImageBitmap(fake);
			} else if ("measure".equals(which)) {
				show(Mode.MEASURE);
				measureStarted = System.currentTimeMillis() - 40000;
				JSONArray stages = new JSONArray();
				String[][] names = {{"White & black", "The brightest and darkest this screen can show."}, {"Red", "How bright red gets, step by step, from dim to full."},
					{"Green", "How bright green gets, step by step, from dim to full."}, {"Blue", "How bright blue gets."}, {"Grays", "Grays from dark to light."},
					{"Game colors", "The game's own colors."}, {"Checking", "The same colors, calibrated."}};
				for (String[] n : names) stages.put(new JSONObject().put("name", n[0]).put("about", n[1]));
				JSONObject next = new JSONObject().put("progress", 0.27).put("stages", stages)
					.put("show", new JSONObject().put("stage", 1).put("title", "Red at 40%").put("step", 7).put("steps", 13).put("color", "#660000"));
				tell(next);
			} else if ("done".equals(which)) {
				show(Mode.DONE);
			} else {
				problem("Couldn't reach the computer", "Check that the phone and the computer are on the same Wi-Fi, then try again.", "Try again", null);
			}
		} catch (JSONException e) {
			// Made-up data; nothing to do.
		}
	}

	/** Says text aloud, unless the voice is switched off. */
	private void speak(String text) {
		if (voiceReady && !settings.getBoolean("quiet", false)) voice.speak(text, TextToSpeech.QUEUE_FLUSH, null, "meter");
	}

	private int dp(float value) {
		return Look.dp(this, value);
	}

	private void readIntent(Intent intent) {
		Uri data = intent.getData();
		if (data != null && "shapematch-meter".equals(data.getScheme())) {
			base = data.getQueryParameter("u");
			session = data.getQueryParameter("s");
		}
	}

	// ---------- Camera ----------

	private void waitForPreview() {
		if (view.isAvailable()) {
			openCamera();
			return;
		}
		view.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
			@Override public void onSurfaceTextureAvailable(SurfaceTexture texture, int w, int h) { openCamera(); }
			@Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int w, int h) {}
			@Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) { return true; }
			@Override public void onSurfaceTextureUpdated(SurfaceTexture texture) {}
		});
	}

	/**
	 * The back camera that gives raw data under manual control, its streams
	 * and a preview; or, on a phone without one, any back camera, which can
	 * still scan the code and send the phone to the web page.
	 */
	private void openCamera() {
		manager = getSystemService(CameraManager.class);
		try {
			String anyBack = null;
			CameraCharacteristics anyBackLooks = null;
			for (String id : manager.getCameraIdList()) {
				CameraCharacteristics c = manager.getCameraCharacteristics(id);
				Integer facing = c.get(CameraCharacteristics.LENS_FACING);
				int[] caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);
				if (facing == null || facing != CameraCharacteristics.LENS_FACING_BACK) continue;
				if (anyBack == null) {
					anyBack = id;
					anyBackLooks = c;
				}
				if (has(caps, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_RAW) && has(caps, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)) {
					cameraId = id;
					characteristics = c;
					canMeasure = true;
					break;
				}
			}
			if (cameraId == null) {
				cameraId = anyBack;
				characteristics = anyBackLooks;
			}
			if (cameraId == null) {
				problem("No camera found", "The meter needs the camera on the back of the phone.", null, null);
				return;
			}
			StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
			previewSize = closest43(map.getOutputSizes(SurfaceTexture.class), 1280);
			Size scanSize = closest43(map.getOutputSizes(ImageFormat.YUV_420_888), 1280);
			if (canMeasure) {
				Size rawSize = largest(map.getOutputSizes(ImageFormat.RAW_SENSOR));
				minFrame = map.getOutputMinFrameDuration(ImageFormat.RAW_SENSOR, rawSize);
				timeRange = characteristics.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE);
				isoRange = characteristics.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE);
				// The sensor's own sensitivity, not below it: some phones reach their
				// lowest ISOs by processing, which may not keep the data linear.
				iso = Math.max(isoRange.getLower(), Math.min(isoRange.getUpper(), BASE_ISO));
				whiteLevel = characteristics.get(CameraCharacteristics.SENSOR_INFO_WHITE_LEVEL);
				blackLevel = characteristics.get(CameraCharacteristics.SENSOR_BLACK_LEVEL_PATTERN);
				Integer arrangement = characteristics.get(CameraCharacteristics.SENSOR_INFO_COLOR_FILTER_ARRANGEMENT);
				cfa = arrangement == null ? 0 : arrangement;
				raw = ImageReader.newInstance(rawSize.getWidth(), rawSize.getHeight(), ImageFormat.RAW_SENSOR, 4);
				raw.setOnImageAvailableListener(reader -> {
					Image image = reader.acquireNextImage();
					if (image == null) return;
					if (!collecting || !images.offer(image)) image.close();
				}, cameraHandler);
			}
			scanFrames = ImageReader.newInstance(scanSize.getWidth(), scanSize.getHeight(), ImageFormat.YUV_420_888, 2);
			scanFrames.setOnImageAvailableListener(this::onScanFrame, cameraHandler);
			SurfaceTexture texture = view.getSurfaceTexture();
			texture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
			preview = new Surface(texture);
			manager.openCamera(cameraId, new CameraDevice.StateCallback() {
				@Override public void onOpened(CameraDevice device) {
					camera = device;
					if (base == null) startScanning(); else connect();
				}
				@Override public void onDisconnected(CameraDevice device) { device.close(); }
				@Override public void onError(CameraDevice device, int error) {
					device.close();
					problem("The camera stopped", "Close the meter and open it again (camera error " + error + ").", null, null);
				}
			}, cameraHandler);
		} catch (CameraAccessException | SecurityException e) {
			problem("Couldn't open the camera", String.valueOf(e.getMessage()), null, null);
		}
	}

	// ---------- Scanning the game's code ----------

	/** The camera as a normal camera (focusing and exposing itself), reading every frame for a code. */
	@SuppressWarnings("deprecation")  // the list form works back to Android 7, which the newer one doesn't
	private void startScanning() {
		show(Mode.SCAN);
		try {
			camera.createCaptureSession(Arrays.asList(preview, scanFrames.getSurface()), new CameraCaptureSession.StateCallback() {
				@Override public void onConfigured(CameraCaptureSession s) {
					capture = s;
					try {
						CaptureRequest.Builder b = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
						b.addTarget(preview);
						b.addTarget(scanFrames.getSurface());
						b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
						capture.setRepeatingRequest(b.build(), null, cameraHandler);
					} catch (CameraAccessException | IllegalStateException e) {
						problem("Couldn't start the camera", String.valueOf(e.getMessage()), null, null);
					}
				}
				@Override public void onConfigureFailed(CameraCaptureSession s) {
					problem("Couldn't start the camera", "Close the meter and open it again.", null, null);
				}
			}, cameraHandler);
		} catch (CameraAccessException e) {
			problem("Couldn't start the camera", String.valueOf(e.getMessage()), null, null);
		}
	}

	/** A frame while scanning: its brightness, read for a code on another thread unless one is being read. */
	private void onScanFrame(ImageReader reader) {
		Image image = reader.acquireLatestImage();
		if (image == null) return;
		if (mode != Mode.SCAN || decoding) {
			image.close();
			return;
		}
		Image.Plane y = image.getPlanes()[0];
		int w = image.getWidth(), h = image.getHeight(), stride = y.getRowStride();
		ByteBuffer buffer = y.getBuffer();
		byte[] luma = new byte[Math.min(buffer.remaining(), stride * h)];
		buffer.get(luma);
		image.close();
		decoding = true;
		scanHandler.post(() -> {
			try {
				String text = QrReader.read(luma, w, Math.min(h, luma.length / stride), stride);
				if (text != null && mode == Mode.SCAN) runOnUiThread(() -> onScanned(text));
			} catch (RuntimeException e) {
				// A bad frame; the next one is read.
			} finally {
				decoding = false;
			}
		});
	}

	/** A code was read: the game's, with its address and session, or something else. */
	private void onScanned(String text) {
		Uri uri = Uri.parse(text);
		String s = uri.getQueryParameter("s");
		if (!"https".equals(uri.getScheme()) || uri.getHost() == null || s == null) {
			words("That's a different code", "Point the camera at the code Shape Match shows under Calibration, With a phone camera.");
			return;
		}
		finder.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
		base = "https://" + uri.getHost() + (uri.getPort() > 0 ? ":" + uri.getPort() : "");
		session = s;
		connect();
	}

	private void rescan() {
		connected = false;
		base = null;
		session = null;
		if (camera != null) startScanning();
	}

	// ---------- Measuring ----------

	/** The camera for measuring (raw, everything fixed by hand), then hello to the game. */
	@SuppressWarnings("deprecation")
	private void connect() {
		if (!canMeasure) {
			String page = base + "/?s=" + Uri.encode(session);
			problem("Measure with the web page", "This phone doesn't let apps read its camera's raw data, so the meter can't measure with it. The web page measures from the browser instead.", "Open the web page",
					() -> startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(page))));
			return;
		}
		show(Mode.CONNECTING);
		words("Connecting…", "Finding Shape Match at " + Uri.parse(base).getHost() + ".");
		try {
			camera.createCaptureSession(Arrays.asList(preview, raw.getSurface()), new CameraCaptureSession.StateCallback() {
				@Override public void onConfigured(CameraCaptureSession s) {
					capture = s;
					shownTime = shownIso = -1;
					showPreview();
					hello();
				}
				@Override public void onConfigureFailed(CameraCaptureSession s) {
					problem("The camera can't take raw pictures", "Scan the code with the phone's camera app instead: the web page measures from the browser.", null, null);
				}
			}, cameraHandler);
		} catch (CameraAccessException e) {
			problem("Couldn't start the camera", String.valueOf(e.getMessage()), null, null);
		}
	}

	/** A request with everything fixed by hand: exposure, ISO, and focus at infinity. */
	private CaptureRequest request(boolean withRaw) throws CameraAccessException {
		CaptureRequest.Builder b = camera.createCaptureRequest(CameraDevice.TEMPLATE_MANUAL);
		b.addTarget(preview);
		if (withRaw) b.addTarget(raw.getSurface());
		long time = clampTime(TIMES[timeIndex]);
		// Automatic white balance only touches the processed preview, never the
		// raw data, and keeps it from looking green.
		b.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
		b.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO);
		b.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF);
		b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF);
		b.set(CaptureRequest.SENSOR_EXPOSURE_TIME, time);
		b.set(CaptureRequest.SENSOR_SENSITIVITY, iso);
		b.set(CaptureRequest.SENSOR_FRAME_DURATION, Math.max(time, minFrame));
		b.set(CaptureRequest.LENS_FOCUS_DISTANCE, 0f);  // infinity: a screen held close is blurred, its pixels averaged
		return b.build();
	}

	private long clampTime(long time) {
		return Math.max(timeRange.getLower(), Math.min(timeRange.getUpper(), time));
	}

	private void showPreview() {
		try {
			capture.setRepeatingRequest(request(false), null, cameraHandler);
		} catch (CameraAccessException | IllegalStateException e) {
			problem("The camera stopped", String.valueOf(e.getMessage()), null, null);
		}
	}

	/** What one or more raw pictures saw, as shares of the sensor's range, black taken off. */
	private static final class Sight {
		final double[] middle = new double[3];  // red, green, blue inside INNER: the disc
		final double[] outer = new double[3];  // between OUTER_FROM and OUTER_TO: the screen around it
		final double[] profile = new double[BINS];  // green, ring by ring from the middle out
		final float[] thumb = new float[THUMB * THUMB];  // green over the measured square
		double clipped;  // share of pixels at the top
		double spread;  // how far the pictures' middles ranged, over their average
		int frames;
	}

	private static double max(double[] rgb) {
		return Math.max(rgb[0], Math.max(rgb[1], rgb[2]));
	}

	private static double total(double[] rgb) {
		return rgb[0] + rgb[1] + rgb[2];
	}

	/**
	 * frames raw pictures, averaged (more, up to MAX_FRAMES, while their
	 * middles disagree, as a flickering screen makes them). One caller at a
	 * time: lining up and measuring share the camera.
	 */
	private synchronized Sight measure(int frames) throws Exception {
		Sight sum = new Sight();
		double lowest = Double.MAX_VALUE, highest = 0;
		if (timeIndex != shownTime || iso != shownIso) {
			showPreview();
			Thread.sleep(150);  // a frame or two at the settings just made
			shownTime = timeIndex;
			shownIso = iso;
		}
		int taken = 0;
		while (taken < frames || (taken < MAX_FRAMES && (highest - lowest) > SPREAD_LIMIT * total(sum.middle) / taken)) {
			images.clear();
			collecting = true;
			capture.capture(request(true), null, cameraHandler);
			Image image = images.poll(3, TimeUnit.SECONDS);
			collecting = false;
			if (image == null) throw new Exception("the camera took no raw picture");
			Sight one = look(image);
			image.close();
			for (int c = 0; c < 3; c++) {
				sum.middle[c] += one.middle[c];
				sum.outer[c] += one.outer[c];
			}
			for (int b = 0; b < BINS; b++) sum.profile[b] += one.profile[b];
			for (int i = 0; i < sum.thumb.length; i++) sum.thumb[i] += one.thumb[i];
			sum.clipped = Math.max(sum.clipped, one.clipped);
			lowest = Math.min(lowest, total(one.middle));
			highest = Math.max(highest, total(one.middle));
			taken++;
		}
		Image left;
		while ((left = images.poll()) != null) left.close();
		for (int c = 0; c < 3; c++) {
			sum.middle[c] /= taken;
			sum.outer[c] /= taken;
		}
		for (int b = 0; b < BINS; b++) sum.profile[b] /= taken;
		for (int i = 0; i < sum.thumb.length; i++) sum.thumb[i] /= taken;
		double mean = total(sum.middle);
		sum.spread = mean > 1e-6 ? (highest - lowest) / mean : 0;
		sum.frames = taken;
		return sum;
	}

	/**
	 * One raw picture, read over the largest square in the middle of the
	 * sensor in 2x2 filter blocks (every few blocks is plenty for averages):
	 * the disc in the middle, the screen around it, the profile out from the
	 * middle and a small picture.
	 */
	private Sight look(Image image) {
		Image.Plane plane = image.getPlanes()[0];
		ByteBuffer buffer = plane.getBuffer().order(ByteOrder.LITTLE_ENDIAN);
		int rowStride = plane.getRowStride();
		int pixelStride = plane.getPixelStride();
		int w = image.getWidth(), h = image.getHeight();
		int side = Math.min(w, h) & ~1;
		int x0 = ((w - side) / 2) & ~1, y0 = ((h - side) / 2) & ~1;
		int step = Math.max(2, (side / SAMPLES) & ~1);
		double half = side / 2.0;
		// Which filter each place in the 2x2 pattern has: 0 red, 1 green, 2 blue.
		int[][] patterns = {{0, 1, 1, 2}, {1, 0, 2, 1}, {1, 2, 0, 1}, {2, 1, 1, 0}};
		int[] filters = patterns[cfa >= 0 && cfa < 4 ? cfa : 0];
		double[] black = new double[4];
		for (int k = 0; k < 4; k++) black[k] = blackLevel == null ? 0 : blackLevel.getOffsetForIndex(k & 1, k >> 1);
		int top = (int) (whiteLevel * CLIPPED);
		Sight s = new Sight();
		long inner = 0, outer = 0, counted = 0, clipped = 0;
		long[] binCount = new long[BINS];
		int[] thumbCount = new int[THUMB * THUMB];
		double[] block = new double[3];
		for (int y = 0; y + 1 < side; y += step) {
			for (int x = 0; x + 1 < side; x += step) {
				double radius = Math.hypot(x + 1 - half, y + 1 - half) / half;
				if (radius >= OUTER_TO) continue;
				block[0] = block[1] = block[2] = 0;
				for (int k = 0; k < 4; k++) {
					int value = buffer.getShort((y0 + y + (k >> 1)) * rowStride + (x0 + x + (k & 1)) * pixelStride) & 0xFFFF;
					if (value >= top) clipped++;
					counted++;
					// Green has two places in the pattern, so each counts half.
					block[filters[k]] += (value - black[k]) / (whiteLevel - black[k]) * (filters[k] == 1 ? 0.5 : 1);
				}
				if (radius < INNER) {
					for (int c = 0; c < 3; c++) s.middle[c] += block[c];
					inner++;
				} else if (radius >= OUTER_FROM) {
					for (int c = 0; c < 3; c++) s.outer[c] += block[c];
					outer++;
				}
				int bin = (int) (radius * BINS);
				s.profile[bin] += block[1];
				binCount[bin]++;
				int cell = (y * THUMB / side) * THUMB + x * THUMB / side;
				s.thumb[cell] += (float) block[1];
				thumbCount[cell]++;
			}
		}
		for (int c = 0; c < 3; c++) {
			s.middle[c] /= Math.max(inner, 1);
			s.outer[c] /= Math.max(outer, 1);
		}
		for (int b = 0; b < BINS; b++) s.profile[b] /= Math.max(binCount[b], 1);
		for (int i = 0; i < s.thumb.length; i++) s.thumb[i] /= Math.max(thumbCount[i], 1);
		s.clipped = (double) clipped / Math.max(counted, 1);
		s.frames = 1;
		return s;
	}

	/**
	 * The disc's edge, as a share of half the square: where the profile
	 * crosses halfway from the middle's brightness to the surround's. Null
	 * when the middle and the surround look alike.
	 */
	private static Double edge(Sight s) {
		double middle = (s.profile[0] + s.profile[1] + s.profile[2] + s.profile[3]) / 4;
		double ring = (s.profile[16] + s.profile[17] + s.profile[18]) / 3;
		if (Math.abs(middle - ring) < 0.15 * Math.max(middle, ring)) return null;
		double halfway = (middle + ring) / 2;
		for (int b = 1; b < BINS; b++) {
			if ((s.profile[b - 1] - halfway) * (s.profile[b] - halfway) <= 0) return (double) b / BINS;
		}
		return null;
	}

	/**
	 * How far the dark disc's middle is from the picture's, as a share of
	 * half the square: the darkness-weighted middle of the small picture.
	 */
	private static double offCenter(Sight s) {
		double middle = (s.profile[0] + s.profile[1]) / 2;
		double ring = (s.profile[16] + s.profile[17] + s.profile[18]) / 3;
		if (ring - middle < 1e-6) return 0;
		double weight = 0, mx = 0, my = 0;
		for (int y = 0; y < THUMB; y++) {
			for (int x = 0; x < THUMB; x++) {
				double dx = (x + 0.5) / THUMB * 2 - 1, dy = (y + 0.5) / THUMB * 2 - 1;
				if (dx * dx + dy * dy >= OUTER_TO * OUTER_TO) continue;
				double dark = Math.max(0, Math.min(1, (ring - s.thumb[y * THUMB + x]) / (ring - middle)));
				weight += dark;
				mx += dark * dx;
				my += dark * dy;
			}
		}
		return weight > 0 ? Math.hypot(mx / weight, my / weight) : 0;
	}

	/** Shows the small picture, turned as the phone is held, with the rings the disc's edge belongs between. */
	private void showPicture(Sight s, boolean good) {
		float brightest = 1e-6f;
		for (float v : s.thumb) brightest = Math.max(brightest, v);
		int[] pixels = new int[THUMB * THUMB];
		for (int i = 0; i < pixels.length; i++) {
			int v = (int) (255 * Math.pow(Math.max(0, s.thumb[i] / brightest), 1 / 2.2));
			pixels[i] = Color.rgb(v, v, v);
		}
		Bitmap small = Bitmap.createBitmap(pixels, THUMB, THUMB, Bitmap.Config.ARGB_8888);
		int size = 480;
		Bitmap big = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
		Canvas canvas = new Canvas(big);
		Integer turn = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
		canvas.save();
		canvas.rotate(turn == null ? 0 : turn, size / 2f, size / 2f);
		canvas.drawBitmap(Bitmap.createScaledBitmap(small, size, size, false), 0, 0, null);
		canvas.restore();
		Look.rings(canvas, size, EDGE_NEAR, EDGE_FAR, good, this);
		runOnUiThread(() -> {
			if (mode == Mode.LINE_UP) picture.setImageBitmap(big);
		});
	}

	/** With white on the screen: the exposure that makes it bright, short of clipping. */
	private JSONObject expose() throws Exception {
		for (int tries = 0; tries < 16; tries++) {
			Sight s = measure(2);
			double brightest = Math.max(max(s.middle), max(s.outer));
			if (s.clipped > CLIP_LIMIT || brightest > 0.8) {
				if (!darker()) break;
			} else if (brightest < 0.3) {
				if (!brighter()) break;
			} else {
				break;
			}
		}
		JSONObject locks = new JSONObject();
		locks.put("exposure", true);
		locks.put("white", true);
		locks.put("white_daylight", false);
		locks.put("exposure_ns", clampTime(TIMES[timeIndex]));
		locks.put("iso", iso);
		locks.put("bracket", bracket());
		return locks;
	}

	/**
	 * The same white at shorter and shorter exposures, [ns, red, green, blue]
	 * each: light in proportion to the time, so the game can check that the
	 * raw data really is linear, and straighten it if not.
	 */
	private JSONArray bracket() throws Exception {
		JSONArray steps = new JSONArray();
		int kept = timeIndex;
		try {
			for (int i = timeIndex; i < TIMES.length && TIMES[i] >= timeRange.getLower(); i++) {
				timeIndex = i;
				Sight s = measure(3);
				steps.put(new JSONArray().put(clampTime(TIMES[i])).put(s.middle[0]).put(s.middle[1]).put(s.middle[2]).put(s.spread));
				if (max(s.middle) < 0.01) break;
			}
		} finally {
			timeIndex = kept;
		}
		return steps;
	}

	/** One step less light: a shorter exposure, else a lower ISO. */
	private boolean darker() {
		if (timeIndex + 1 < TIMES.length && TIMES[timeIndex + 1] >= timeRange.getLower()) {
			timeIndex++;
			return true;
		}
		if (iso > isoRange.getLower()) {
			iso = Math.max(isoRange.getLower(), iso / 2);
			return true;
		}
		return false;
	}

	/** One step more light: a longer exposure, else a higher ISO. */
	private boolean brighter() {
		if (timeIndex > 0 && TIMES[timeIndex - 1] <= timeRange.getUpper()) {
			timeIndex--;
			return true;
		}
		if (iso < isoRange.getUpper()) {
			iso = Math.min(isoRange.getUpper(), iso * 2);
			return true;
		}
		return false;
	}

	/**
	 * While waiting for Start: shows what the camera sees and tells the game
	 * where it sees the dark disc's edge, so the game sizes the disc to fit.
	 */
	private void lineUp() {
		new Thread(() -> {
			String said = "";
			while (connected && !isFinishing()) {
				try {
					if (measuring || mode != Mode.LINE_UP) {
						Thread.sleep(300);
						continue;
					}
					Sight s = measure(1);
					if (measuring || mode != Mode.LINE_UP) continue;
					double brightest = Math.max(max(s.middle), max(s.outer));
					if (s.clipped > CLIP_LIMIT || brightest > 0.8) darker();
					else if (brightest < 0.25) brighter();
					Double edge = edge(s);
					boolean centered = edge != null && offCenter(s) < 0.12;
					boolean good = centered && edge >= EDGE_NEAR && edge <= EDGE_FAR;
					showPicture(s, good);
					String heading;
					if (edge == null) {
						heading = "Find the dark circle";
						words(heading, "Rest the phone with its camera facing the computer screen, a few centimeters away. Then drag the dark circle on the computer until it shows up in the picture above.");
					} else if (!centered) {
						heading = "Center the circle";
						words(heading, "On the computer, drag the dark circle a little, until it sits in the middle of the picture above.");
					} else if (!good) {
						heading = "Hold still";
						words(heading, "The computer is sizing the circle to fit between the rings.");
					} else {
						heading = "Lined up!";
						words(heading, "Tap Start measuring, then leave the phone and the circle where they are for about two minutes.");
					}
					if (!heading.equals(said) && (good || said.isEmpty())) speak(heading);
					said = heading;
					JSONObject view = new JSONObject();
					view.put("edge", edge == null ? JSONObject.NULL : edge);
					view.put("ripple", 0);
					post("/aim", view);
				} catch (InterruptedException e) {
					return;
				} catch (IllegalStateException e) {
					connected = false;  // the game ended this session
					problem("This session has ended", "Shape Match closed the calibration. Open it again on the computer and scan the new code.", "Scan the new code", this::rescan);
				} catch (Exception e) {
					try {
						Thread.sleep(1000);
					} catch (InterruptedException stop) {
						return;
					}
				}
			}
		}).start();
	}

	// ---------- Talking to the game ----------

	private void hello() {
		new Thread(() -> {
			try {
				JSONObject info = new JSONObject();
				info.put("raw", true);
				info.put("version", VERSION);
				info.put("manual", true);
				info.put("white", true);
				info.put("direct", true);
				info.put("model", Build.MANUFACTURER + " " + Build.MODEL);
				info.put("android", Build.VERSION.RELEASE);
				info.put("cfa", cfa);
				info.put("white_level", whiteLevel);
				JSONArray black = new JSONArray();
				for (int k = 0; k < 4; k++) black.put(blackLevel == null ? 0 : blackLevel.getOffsetForIndex(k & 1, k >> 1));
				info.put("black_level", black);
				matrix(info, "color_matrix1", characteristics.get(CameraCharacteristics.SENSOR_COLOR_TRANSFORM1));
				matrix(info, "color_matrix2", characteristics.get(CameraCharacteristics.SENSOR_COLOR_TRANSFORM2));
				matrix(info, "calibration1", characteristics.get(CameraCharacteristics.SENSOR_CALIBRATION_TRANSFORM1));
				matrix(info, "calibration2", characteristics.get(CameraCharacteristics.SENSOR_CALIBRATION_TRANSFORM2));
				matrix(info, "forward_matrix1", characteristics.get(CameraCharacteristics.SENSOR_FORWARD_MATRIX1));
				matrix(info, "forward_matrix2", characteristics.get(CameraCharacteristics.SENSOR_FORWARD_MATRIX2));
				Integer illuminant1 = characteristics.get(CameraCharacteristics.SENSOR_REFERENCE_ILLUMINANT1);
				Byte illuminant2 = characteristics.get(CameraCharacteristics.SENSOR_REFERENCE_ILLUMINANT2);
				info.put("illuminant1", illuminant1 == null ? 0 : illuminant1);
				info.put("illuminant2", illuminant2 == null ? 0 : illuminant2);
				JSONObject answer = post("/hello", info);
				if (answer.optInt("meter_version", 0) > VERSION) {
					// The game has a newer meter: offer its download.
					problem("A newer meter is ready", "Shape Match on the computer has a newer version of this app. Tap Update, open the download to install it, then scan the code again.", "Update",
							() -> startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(base + "/meter.apk?s=" + Uri.encode(session)))));
					return;
				}
				speak("Connected");
				show(Mode.LINE_UP);
				words("Find the dark circle", "Rest the phone with its camera facing the computer screen, a few centimeters away.");
				if (!connected) {
					connected = true;
					lineUp();
				}
			} catch (IllegalStateException e) {
				problem("That code has expired", "Shape Match made a new code since. Scan the one on the computer now.", "Scan again", this::rescan);
			} catch (Exception e) {
				problem("Couldn't reach the computer", "Check that the phone and the computer are on the same Wi-Fi, then try again.", "Try again", this::connect);
			}
		}).start();
	}

	/** A camera color matrix, as nine numbers row by row. */
	private static void matrix(JSONObject info, String key, ColorSpaceTransform m) throws JSONException {
		if (m == null) return;
		JSONArray values = new JSONArray();
		for (int row = 0; row < 3; row++) {
			for (int col = 0; col < 3; col++) values.put(m.getElement(col, row).doubleValue());
		}
		info.put(key, values);
	}

	private void startMeasuring() {
		if (measuring) return;
		measuring = true;
		stuck = false;
		shownStage = -1;
		measureStarted = System.currentTimeMillis();
		show(Mode.MEASURE);
		words("Getting ready…", "Setting the camera up on white. Keep the phone still.");
		speak("Starting. Keep the phone still.");
		new Thread(() -> {
			try {
				JSONObject reading = new JSONObject();
				reading.put("id", -1);
				JSONObject next = post("/reading", reading);
				while (!next.optBoolean("done", false)) {
					tell(next);
					reading = new JSONObject();
					reading.put("id", next.getInt("id"));
					if (next.optBoolean("lock", false)) reading.put("locks", expose());
					if (next.optBoolean("darker", false) && !stuck) stuck = !darker();
					Thread.sleep(next.optInt("settle", 400));
					Sight s = measure(next.optInt("frames", 3));
					reading.put("rgb", new JSONArray().put(s.middle[0]).put(s.middle[1]).put(s.middle[2]));
					reading.put("outer", new JSONArray().put(s.outer[0]).put(s.outer[1]).put(s.outer[2]));
					Double edge = edge(s);
					reading.put("edge", edge == null ? JSONObject.NULL : edge);
					reading.put("clip", s.clipped);
					reading.put("spread", s.spread);
					reading.put("frames", s.frames);
					reading.put("exposure_ns", clampTime(TIMES[timeIndex]));
					reading.put("iso", iso);
					reading.put("cant_darken", stuck);
					reading.put("raw", true);
					next = post("/reading", reading);
				}
				measuring = false;
				show(Mode.DONE);
				speak("All done! The result is on the computer.");
			} catch (IllegalStateException e) {
				measuring = false;
				problem("This session has ended", "Shape Match closed the calibration. Open it again on the computer and scan the new code.", "Scan the new code", this::rescan);
			} catch (Exception e) {
				measuring = false;
				problem("Measuring stopped", "Lost touch with the computer (" + e.getMessage() + "). Check the Wi-Fi and start again.", "Start again", () -> show(Mode.LINE_UP));
			}
		}).start();
	}

	/**
	 * Shows (and on a new stage, says) what the computer is showing now, from
	 * its answer: the color, its name, what the stage is for, every stage as a
	 * chip, how far along, and about how long is left.
	 */
	private void tell(JSONObject next) {
		JSONObject now = next.optJSONObject("show");
		JSONArray stages = next.optJSONArray("stages");
		double progress = next.optDouble("progress", 0);
		String note = next.optString("text", "");
		if (now == null || stages == null) return;
		int stage = now.optInt("stage", 0);
		JSONObject about = stages.optJSONObject(stage);
		String name = about == null ? "" : about.optString("name");
		String why = about == null ? "" : about.optString("about");
		long elapsed = System.currentTimeMillis() - measureStarted;
		String left = "";
		if (progress > 0.05) {
			long seconds = Math.round(elapsed * (1 - progress) / progress / 1000.0);
			left = seconds > 90 ? "About " + Math.round(seconds / 60.0) + " minutes left." : seconds > 20 ? "Less than a minute and a half left." : "Almost done.";
		}
		String heading = now.optString("title");
		String detail = (note.isEmpty() ? why : note) + "\n" + now.optInt("step") + " of " + now.optInt("steps") + (left.isEmpty() ? "" : " · " + left);
		int color;
		try {
			color = Color.parseColor(now.optString("color", "#ffffff"));
		} catch (IllegalArgumentException e) {
			color = Color.WHITE;
		}
		int shown = color;
		runOnUiThread(() -> {
			swatch.show(shown);
			title.setText(heading);
			body.setText(detail);
			bar.set((float) progress);
			if (stage != shownStage) {
				chips.removeAllViews();
				for (int i = 0; i < stages.length(); i++) {
					JSONObject s = stages.optJSONObject(i);
					TextView chip = Look.chip(this, s == null ? "" : s.optString("name"), i < stage ? -1 : i == stage ? 0 : 1);
					LinearLayout.LayoutParams at = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
					at.rightMargin = dp(6);
					chips.addView(chip, at);
				}
				View current = chips.getChildAt(stage);
				if (current != null) chipScroll.post(() -> chipScroll.smoothScrollTo(Math.max(0, current.getLeft() - (chipScroll.getWidth() - current.getWidth()) / 2), 0));
			}
		});
		if (stage != shownStage) {
			shownStage = stage;
			speak("Now: " + name + ". " + why);
		}
	}

	/** Posts body to the game and returns its answer. The game makes its own certificate, so it isn't checked; the session code is what proves it's the right game. */
	private JSONObject post(String path, JSONObject body) throws Exception {
		SSLContext ssl = SSLContext.getInstance("TLS");
		ssl.init(null, new TrustManager[] {new X509TrustManager() {
			@Override public void checkClientTrusted(X509Certificate[] chain, String type) {}
			@Override public void checkServerTrusted(X509Certificate[] chain, String type) {}
			@Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
		}}, new SecureRandom());
		Exception last = null;
		for (int attempt = 0; attempt < 4; attempt++) {
			try {
				HttpsURLConnection c = (HttpsURLConnection) new URL(base + path + "?s=" + Uri.encode(session)).openConnection();
				c.setSSLSocketFactory(ssl.getSocketFactory());
				c.setHostnameVerifier((host, s) -> true);
				c.setConnectTimeout(5000);
				c.setReadTimeout(15000);
				c.setRequestMethod("POST");
				c.setDoOutput(true);
				c.setRequestProperty("Content-Type", "application/json");
				byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
				try (OutputStream out = c.getOutputStream()) {
					out.write(bytes);
				}
				int code = c.getResponseCode();
				InputStream in = code < 400 ? c.getInputStream() : c.getErrorStream();
				ByteArrayOutputStream answer = new ByteArrayOutputStream();
				byte[] chunk = new byte[4096];
				for (int n; in != null && (n = in.read(chunk)) > 0; ) answer.write(chunk, 0, n);
				String text = answer.toString("UTF-8");
				if (code == 403) throw new IllegalStateException(text);
				return text.trim().startsWith("{") ? new JSONObject(text) : new JSONObject();
			} catch (IllegalStateException e) {
				throw e;
			} catch (Exception e) {
				last = e;
				Thread.sleep(500);
			}
		}
		throw last;
	}

	// ---------- Helpers ----------

	private static boolean has(int[] values, int wanted) {
		if (values == null) return false;
		for (int v : values) if (v == wanted) return true;
		return false;
	}

	private static Size largest(Size[] sizes) {
		Size best = sizes[0];
		for (Size s : sizes) if ((long) s.getWidth() * s.getHeight() > (long) best.getWidth() * best.getHeight()) best = s;
		return best;
	}

	/** The 4:3 size nearest width wide (the scan reads it, the preview fills a 3:4 card), else the nearest at all. */
	private static Size closest43(Size[] sizes, int width) {
		Size best = null;
		for (Size s : sizes) {
			if (s.getWidth() * 3 != s.getHeight() * 4) continue;
			if (best == null || Math.abs(s.getWidth() - width) < Math.abs(best.getWidth() - width)) best = s;
		}
		return best != null ? best : closest(sizes, width, width * 3 / 4);
	}

	private static Size closest(Size[] sizes, int w, int h) {
		Size best = sizes[0];
		long bestScore = Long.MAX_VALUE;
		for (Size s : sizes) {
			long score = Math.abs((long) s.getWidth() * s.getHeight() - (long) w * h);
			if (score < bestScore) {
				bestScore = score;
				best = s;
			}
		}
		return best;
	}
}
