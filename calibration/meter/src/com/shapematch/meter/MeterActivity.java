package com.shapematch.meter;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
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
import android.util.Range;
import android.util.Size;
import android.view.Gravity;
import android.view.Surface;
import android.view.TextureView;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
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
 * The game's web page opens it with shapematch-meter://connect?u=address&s=session.
 * It then works like the page: it posts what it sees in the middle of the
 * picture to the game, and the game answers with the next patch. Exposure,
 * ISO and focus are fixed by hand: exposure so white comes out bright but not
 * clipped, and focus at infinity, so a screen held close is blurred.
 */
public class MeterActivity extends Activity {
	private static final int ASK_CAMERA = 1;
	private static final int VERSION = 4;  // as android:versionCode; the game says which it expects
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
	private static final int INK = Color.rgb(59, 47, 74);

	private String base;  // the game's address, https://host:port
	private String session;
	private TextView status;
	private ProgressBar bar;
	private Button start;
	private TextureView view;
	private ImageView picture;  // what the sensor sees, with the rings the disc's edge belongs between
	private volatile boolean connected;
	private HandlerThread cameraThread;
	private Handler cameraHandler;
	private CameraDevice camera;
	private CameraCaptureSession capture;
	private CameraCharacteristics characteristics;
	private ImageReader raw;
	private Surface preview;
	private Size previewSize;
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
	private boolean measuring;
	private boolean stuck;  // can't get any darker

	@Override
	protected void onCreate(Bundle state) {
		super.onCreate(state);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		buildUi();
		readIntent(getIntent());
		cameraThread = new HandlerThread("camera");
		cameraThread.start();
		cameraHandler = new Handler(cameraThread.getLooper());
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
		if (camera != null && base != null) hello();
	}

	@Override
	protected void onDestroy() {
		super.onDestroy();
		if (capture != null) capture.close();
		if (camera != null) camera.close();
		if (raw != null) raw.close();
		cameraThread.quitSafely();
	}

	@Override
	public void onRequestPermissionsResult(int code, String[] permissions, int[] results) {
		if (code == ASK_CAMERA && results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
			waitForPreview();
		} else {
			say("The meter needs the camera to measure the screen. Allow it in the phone's settings, then open the meter again.");
		}
	}

	// ---------- Screen ----------

	private void buildUi() {
		LinearLayout page = new LinearLayout(this);
		page.setOrientation(LinearLayout.VERTICAL);
		page.setPadding(dp(18), dp(18), dp(18), dp(18));
		page.setBackgroundColor(Color.rgb(191, 229, 255));
		TextView title = new TextView(this);
		title.setText("Shape Match Meter");
		title.setTextSize(24);
		title.setTypeface(Typeface.DEFAULT_BOLD);
		title.setTextColor(INK);
		page.addView(title);
		// The camera's preview only keeps the camera running; what is shown is
		// the raw picture itself, the part measured, so lining up is exact.
		view = new TextureView(this);
		page.addView(view, new LinearLayout.LayoutParams(dp(2), dp(2)));
		picture = new ImageView(this);
		picture.setScaleType(ImageView.ScaleType.FIT_CENTER);
		picture.setBackgroundColor(Color.BLACK);
		LinearLayout.LayoutParams square = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
		square.topMargin = dp(10);
		square.bottomMargin = dp(12);
		page.addView(picture, square);
		status = new TextView(this);
		status.setTextSize(18);
		status.setTextColor(INK);
		page.addView(status);
		bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
		bar.setMax(1000);
		page.addView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(28)));
		start = new Button(this);
		start.setText("Start");
		start.setTextSize(20);
		start.setAllCaps(false);
		start.setTextColor(INK);
		GradientDrawable green = new GradientDrawable();
		green.setColor(Color.rgb(123, 216, 143));
		green.setCornerRadius(dp(16));
		green.setStroke(dp(3), INK);
		start.setBackground(green);
		start.setEnabled(false);
		start.setOnClickListener(v -> startMeasuring());
		LinearLayout.LayoutParams wide = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64));
		wide.topMargin = dp(12);
		page.addView(start, wide);
		setContentView(page);
		say("Starting the camera…");
	}

	private int dp(int value) {
		return Math.round(value * getResources().getDisplayMetrics().density);
	}

	private void say(String text) {
		runOnUiThread(() -> status.setText(text));
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

	/** The back camera that gives raw data under manual control, its raw stream and a preview. */
	private void openCamera() {
		CameraManager manager = getSystemService(CameraManager.class);
		try {
			String chosen = null;
			for (String id : manager.getCameraIdList()) {
				CameraCharacteristics c = manager.getCameraCharacteristics(id);
				Integer facing = c.get(CameraCharacteristics.LENS_FACING);
				int[] caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);
				if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK && has(caps, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_RAW)
						&& has(caps, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)) {
					chosen = id;
					characteristics = c;
					break;
				}
			}
			if (chosen == null) {
				say("This phone's camera can't give its raw data to apps, so the meter can't measure with it. Use the web page's camera mode instead, or calibrate by eye.");
				return;
			}
			StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
			Size rawSize = largest(map.getOutputSizes(ImageFormat.RAW_SENSOR));
			minFrame = map.getOutputMinFrameDuration(ImageFormat.RAW_SENSOR, rawSize);
			previewSize = closest(map.getOutputSizes(SurfaceTexture.class), 1280, 720);
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
			SurfaceTexture texture = view.getSurfaceTexture();
			texture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
			preview = new Surface(texture);
			manager.openCamera(chosen, new CameraDevice.StateCallback() {
				@Override public void onOpened(CameraDevice device) {
					camera = device;
					startSession();
				}
				@Override public void onDisconnected(CameraDevice device) { device.close(); }
				@Override public void onError(CameraDevice device, int error) {
					device.close();
					say("The camera stopped working (error " + error + "). Close the meter and open it again.");
				}
			}, cameraHandler);
		} catch (CameraAccessException | SecurityException e) {
			say("Couldn't open the camera: " + e.getMessage());
		}
	}

	@SuppressWarnings("deprecation")  // the list form works back to Android 7, which the newer one doesn't
	private void startSession() {
		try {
			camera.createCaptureSession(Arrays.asList(preview, raw.getSurface()), new CameraCaptureSession.StateCallback() {
				@Override public void onConfigured(CameraCaptureSession s) {
					capture = s;
					showPreview();
					if (base == null || session == null) {
						say("Open the meter from the page the Shape Match code opens: scan the code on the screen with the phone's camera, then tap Open the Meter app.");
					} else {
						hello();
					}
				}
				@Override public void onConfigureFailed(CameraCaptureSession s) {
					say("The camera couldn't be set up for raw pictures. Use the web page's camera mode instead.");
				}
			}, cameraHandler);
		} catch (CameraAccessException e) {
			say("Couldn't start the camera: " + e.getMessage());
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
			say("The camera's preview stopped: " + e.getMessage());
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
		Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
		ring.setStyle(Paint.Style.STROKE);
		ring.setStrokeWidth(5);
		ring.setColor(good ? Color.rgb(60, 200, 90) : Color.rgb(255, 150, 40));
		ring.setPathEffect(new DashPathEffect(new float[] {18, 12}, 0));
		for (double r : new double[] {EDGE_NEAR, EDGE_FAR}) canvas.drawCircle(size / 2f, size / 2f, (float) (r * size / 2), ring);
		runOnUiThread(() -> picture.setImageBitmap(big));
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
			while (connected && !isFinishing()) {
				try {
					if (measuring) {
						Thread.sleep(500);
						continue;
					}
					Sight s = measure(1);
					if (measuring) continue;
					double brightest = Math.max(max(s.middle), max(s.outer));
					if (s.clipped > CLIP_LIMIT || brightest > 0.8) darker();
					else if (brightest < 0.25) brighter();
					Double edge = edge(s);
					boolean centered = edge != null && offCenter(s) < 0.12;
					boolean good = centered && edge >= EDGE_NEAR && edge <= EDGE_FAR;
					showPicture(s, good);
					if (edge == null) {
						say("Can't see the dark circle. On the computer, drag the circle until it is under the phone's camera: the picture above shows what the camera sees.");
					} else if (!centered) {
						say("Drag the circle on the computer until it sits in the middle of the picture above.");
					} else if (!good) {
						say("Hold still: the computer is sizing the circle to fit between the rings.");
					} else {
						say("Lined up. Tap Start, and don't move the phone or the circle until it's done.");
					}
					JSONObject view = new JSONObject();
					view.put("edge", edge == null ? JSONObject.NULL : edge);
					view.put("ripple", 0);
					post("/aim", view);
				} catch (InterruptedException e) {
					return;
				} catch (IllegalStateException e) {
					connected = false;  // the game ended this session
					say(e.getMessage());
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
					// The game has a newer meter: Start becomes its download.
					runOnUiThread(() -> {
						start.setText("Update the meter");
						start.setOnClickListener(v -> startActivity(new Intent(Intent.ACTION_VIEW,
								Uri.parse(base + "/meter.apk?s=" + Uri.encode(session)))));
						start.setEnabled(true);
					});
					say("This meter is out of date. Tap Update the meter, open the download to install it, then open the meter again from the page.");
					return;
				}
				runOnUiThread(() -> start.setEnabled(true));
				say("Connected. Rest the phone with its camera facing the screen, a few centimeters from it.");
				if (!connected) {
					connected = true;
					lineUp();
				}
			} catch (Exception e) {
				say("Couldn't reach the screen: " + e.getMessage() + ". Both must be on the same Wi-Fi; open the meter again from the page.");
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
		start.setEnabled(false);
		new Thread(() -> {
			try {
				JSONObject reading = new JSONObject();
				reading.put("id", -1);
				JSONObject next = post("/reading", reading);
				while (!next.optBoolean("done", false)) {
					int progress = (int) (next.optDouble("progress", 0) * 1000);
					runOnUiThread(() -> bar.setProgress(progress));
					reading = new JSONObject();
					reading.put("id", next.getInt("id"));
					if (next.optBoolean("lock", false)) {
						say("Setting the camera up on white…");
						reading.put("locks", expose());
					}
					if (next.optBoolean("darker", false) && !stuck) stuck = !darker();
					say(next.optString("text", "").isEmpty() ? "Measuring. Keep the phone still." : next.optString("text"));
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
				runOnUiThread(() -> bar.setProgress(1000));
				say(next.optString("text", "Done. Look at the results on the screen.") + "\n\nTo measure again, tap Try again on the screen, then Start here.");
			} catch (Exception e) {
				say("Stopped: " + e.getMessage() + ". Start again from the screen.");
			}
			measuring = false;
			runOnUiThread(() -> start.setEnabled(true));
		}).start();
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
