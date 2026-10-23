package com.shapematch.meter;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.LinearGradient;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.TextView;

/**
 * The meter's look, matching the game's: its pastel colors and dark ink
 * outlines, a rounded font (Nunito, in assets with its license), and the
 * few drawn pieces the screens use.
 */
final class Look {
	private Look() {}

	static final int INK = Color.rgb(59, 47, 74);
	static final int INK_SOFT = Color.argb(170, 59, 47, 74);
	static final int SKY = Color.rgb(191, 229, 255);
	static final int PAPER = Color.rgb(255, 250, 240);
	static final int GO = Color.rgb(123, 216, 143);
	static final int SUN = Color.rgb(255, 209, 102);
	static final int PINK = Color.rgb(255, 180, 162);
	static final int SCREEN = Color.rgb(44, 42, 58);

	private static Typeface bold, regular;

	/** Nunito at weight, where the phone can set a variable font's weight (Android 8 on). */
	static Typeface font(Context context, boolean heavy) {
		if (bold == null) {
			if (Build.VERSION.SDK_INT >= 26) {
				bold = new Typeface.Builder(context.getAssets(), "nunito.ttf").setFontVariationSettings("'wght' 850").build();
				regular = new Typeface.Builder(context.getAssets(), "nunito.ttf").setFontVariationSettings("'wght' 600").build();
			}
			if (bold == null) bold = Typeface.DEFAULT_BOLD;
			if (regular == null) regular = Typeface.DEFAULT;
		}
		return heavy ? bold : regular;
	}

	static int dp(Context context, float value) {
		return Math.round(value * context.getResources().getDisplayMetrics().density);
	}

	static TextView text(Context context, String words, float size, boolean heavy, int color) {
		TextView t = new TextView(context);
		t.setText(words);
		t.setTextSize(size);
		t.setTypeface(font(context, heavy));
		t.setTextColor(color);
		t.setLineSpacing(0, 1.1f);
		return t;
	}

	/** A rounded fill with the game's ink outline. */
	static GradientDrawable round(Context context, int fill, float radius, float outline) {
		GradientDrawable d = new GradientDrawable();
		d.setColor(fill);
		d.setCornerRadius(dp(context, radius));
		if (outline > 0) d.setStroke(dp(context, outline), INK);
		return d;
	}

	/** A big pill button, as the game's. */
	static TextView button(Context context, String words, int fill) {
		TextView b = text(context, words, 20, true, INK);
		b.setGravity(Gravity.CENTER);
		b.setBackground(round(context, fill, 22, 2.5f));
		b.setPadding(dp(context, 20), dp(context, 14), dp(context, 20), dp(context, 14));
		b.setElevation(dp(context, 3));
		return b;
	}

	/** A small rounded label: done (green, ticked), now (yellow) or to come (faint). */
	static TextView chip(Context context, String words, int state) {
		TextView c = text(context, (state < 0 ? "✓ " : "") + words, 13, state == 0, state > 0 ? INK_SOFT : INK);
		c.setBackground(round(context, state < 0 ? GO : state == 0 ? SUN : Color.argb(200, 255, 255, 255), 14, state == 0 ? 2 : 1));
		c.setPadding(dp(context, 10), dp(context, 4), dp(context, 10), dp(context, 4));
		return c;
	}

	/** Clips a view to rounded corners. */
	static void clipRound(View view, float radius) {
		view.setOutlineProvider(new ViewOutlineProvider() {
			@Override public void getOutline(View v, Outline outline) {
				outline.setRoundRect(0, 0, v.getWidth(), v.getHeight(), dp(v.getContext(), radius));
			}
		});
		view.setClipToOutline(true);
	}

	/** The page's sky, fading to paper. */
	static GradientDrawable sky() {
		return new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] {Color.rgb(207, 234, 255), Color.rgb(255, 246, 224)});
	}

	/** A frame that keeps a width to height ratio, as large as it fits. */
	static final class Aspect extends FrameLayout {
		private final float ratio;  // height over width

		Aspect(Context context, float ratio) {
			super(context);
			this.ratio = ratio;
		}

		@Override
		protected void onMeasure(int widthSpec, int heightSpec) {
			int w = MeasureSpec.getSize(widthSpec), h = MeasureSpec.getSize(heightSpec);
			int height = Math.round(w * ratio);
			if (MeasureSpec.getMode(heightSpec) != MeasureSpec.UNSPECIFIED && height > h) {
				height = h;
				w = Math.round(h / ratio);
			}
			super.onMeasure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));
		}
	}

	/** The game's shapes, small: a pink circle, a yellow star and a green square. */
	static final class Logo extends View {
		private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG), line = new Paint(Paint.ANTI_ALIAS_FLAG);

		Logo(Context context) {
			super(context);
			line.setStyle(Paint.Style.STROKE);
			line.setColor(INK);
			line.setStrokeWidth(dp(context, 2));
			line.setStrokeJoin(Paint.Join.ROUND);
		}

		@Override
		protected void onDraw(Canvas canvas) {
			float h = getHeight(), r = h * 0.3f, y = h / 2;
			fill.setColor(PINK);
			canvas.drawCircle(r + 2, y, r, fill);
			canvas.drawCircle(r + 2, y, r, line);
			Path star = new Path();
			float cx = r * 3.4f, outer = r * 1.15f, inner = outer * 0.48f;
			for (int i = 0; i < 10; i++) {
				double a = -Math.PI / 2 + i * Math.PI / 5;
				float rr = i % 2 == 0 ? outer : inner;
				float px = cx + (float) Math.cos(a) * rr, py = y + 1 + (float) Math.sin(a) * rr;
				if (i == 0) star.moveTo(px, py); else star.lineTo(px, py);
			}
			star.close();
			fill.setColor(SUN);
			canvas.drawPath(star, fill);
			canvas.drawPath(star, line);
			RectF square = new RectF(r * 5.0f, y - r * 0.9f, r * 6.8f, y + r * 0.9f);
			fill.setColor(GO);
			canvas.drawRoundRect(square, r * 0.3f, r * 0.3f, fill);
			canvas.drawRoundRect(square, r * 0.3f, r * 0.3f, line);
		}
	}

	/** Over the camera while scanning: bright corners to aim with, and a line sweeping down. */
	static final class Viewfinder extends View {
		private final Paint corner = new Paint(Paint.ANTI_ALIAS_FLAG), sweep = new Paint(), dim = new Paint();
		private final ValueAnimator animator = ValueAnimator.ofFloat(0, 1);
		private float at;

		Viewfinder(Context context) {
			super(context);
			corner.setStyle(Paint.Style.STROKE);
			corner.setStrokeWidth(dp(context, 5));
			corner.setStrokeCap(Paint.Cap.ROUND);
			corner.setColor(SUN);
			dim.setColor(Color.argb(90, 0, 0, 0));
			animator.setDuration(1800);
			animator.setRepeatMode(ValueAnimator.REVERSE);
			animator.setRepeatCount(ValueAnimator.INFINITE);
			animator.addUpdateListener(a -> {
				at = (float) a.getAnimatedValue();
				invalidate();
			});
		}

		@Override
		protected void onAttachedToWindow() {
			super.onAttachedToWindow();
			animator.start();
		}

		@Override
		protected void onDetachedFromWindow() {
			animator.cancel();
			super.onDetachedFromWindow();
		}

		@Override
		protected void onDraw(Canvas canvas) {
			float w = getWidth(), h = getHeight(), side = Math.min(w, h) * 0.72f;
			float left = (w - side) / 2, top = (h - side) / 2, len = side * 0.18f;
			// Dim around the square, so it stands out.
			canvas.drawRect(0, 0, w, top, dim);
			canvas.drawRect(0, top + side, w, h, dim);
			canvas.drawRect(0, top, left, top + side, dim);
			canvas.drawRect(left + side, top, w, top + side, dim);
			float[][] corners = {{left, top, 1, 1}, {left + side, top, -1, 1}, {left, top + side, 1, -1}, {left + side, top + side, -1, -1}};
			for (float[] c : corners) {
				canvas.drawLine(c[0], c[1], c[0] + c[2] * len, c[1], corner);
				canvas.drawLine(c[0], c[1], c[0], c[1] + c[3] * len, corner);
			}
			float y = top + side * at;
			sweep.setShader(new LinearGradient(0, y - dp(getContext(), 18), 0, y, Color.argb(0, 255, 209, 102), Color.argb(200, 255, 209, 102), Shader.TileMode.CLAMP));
			canvas.drawRect(left + dp(getContext(), 8), y - dp(getContext(), 18), left + side - dp(getContext(), 8), y, sweep);
		}
	}

	/** What the screen shows now: its color in a circle on white, as the computer draws it; or a big tick when done. */
	static final class Swatch extends View {
		private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
		private int color = Color.WHITE;
		private boolean done, problem;
		private float pulse;
		private final ValueAnimator animator = ValueAnimator.ofFloat(0, 1);

		Swatch(Context context) {
			super(context);
			animator.setDuration(1400);
			animator.setRepeatMode(ValueAnimator.REVERSE);
			animator.setRepeatCount(ValueAnimator.INFINITE);
			animator.addUpdateListener(a -> {
				pulse = (float) a.getAnimatedValue();
				invalidate();
			});
		}

		void show(int color) {
			this.color = color;
			done = problem = false;
			invalidate();
		}

		void done() {
			done = true;
			problem = false;
			invalidate();
		}

		void problem() {
			problem = true;
			done = false;
			invalidate();
		}

		@Override
		protected void onAttachedToWindow() {
			super.onAttachedToWindow();
			animator.start();
		}

		@Override
		protected void onDetachedFromWindow() {
			animator.cancel();
			super.onDetachedFromWindow();
		}

		@Override
		protected void onDraw(Canvas canvas) {
			float w = getWidth(), h = getHeight(), r = Math.min(w, h) * 0.3f;
			canvas.drawColor(Color.WHITE);
			paint.setStyle(Paint.Style.FILL);
			if (done) {
				paint.setColor(GO);
				canvas.drawCircle(w / 2, h / 2, r, paint);
				paint.setStyle(Paint.Style.STROKE);
				paint.setStrokeWidth(r * 0.16f);
				paint.setStrokeCap(Paint.Cap.ROUND);
				paint.setStrokeJoin(Paint.Join.ROUND);
				paint.setColor(Color.WHITE);
				Path tick = new Path();
				tick.moveTo(w / 2 - r * 0.45f, h / 2);
				tick.lineTo(w / 2 - r * 0.1f, h / 2 + r * 0.35f);
				tick.lineTo(w / 2 + r * 0.5f, h / 2 - r * 0.35f);
				canvas.drawPath(tick, paint);
				return;
			}
			if (problem) {
				// A warning sign: a pink circle with an exclamation mark.
				paint.setColor(PINK);
				canvas.drawCircle(w / 2, h / 2, r, paint);
				paint.setStyle(Paint.Style.STROKE);
				paint.setStrokeWidth(dp(getContext(), 3));
				paint.setColor(INK);
				canvas.drawCircle(w / 2, h / 2, r, paint);
				paint.setStrokeWidth(r * 0.18f);
				paint.setStrokeCap(Paint.Cap.ROUND);
				canvas.drawLine(w / 2, h / 2 - r * 0.5f, w / 2, h / 2 + r * 0.12f, paint);
				paint.setStyle(Paint.Style.FILL);
				canvas.drawCircle(w / 2, h / 2 + r * 0.45f, r * 0.1f, paint);
				return;
			}
			// A soft halo breathing around the color, so waiting feels alive.
			paint.setColor(Color.argb((int) (40 + 50 * pulse), Color.red(SUN), Color.green(SUN), Color.blue(SUN)));
			canvas.drawCircle(w / 2, h / 2, r * (1.12f + 0.08f * pulse), paint);
			paint.setColor(color);
			canvas.drawCircle(w / 2, h / 2, r, paint);
			paint.setStyle(Paint.Style.STROKE);
			paint.setStrokeWidth(dp(getContext(), 3));
			paint.setColor(INK);
			canvas.drawCircle(w / 2, h / 2, r, paint);
		}
	}

	/** A rounded progress bar. */
	static final class Bar extends View {
		private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
		private float value;

		Bar(Context context) {
			super(context);
		}

		void set(float value) {
			this.value = Math.max(0, Math.min(1, value));
			invalidate();
		}

		@Override
		protected void onDraw(Canvas canvas) {
			float w = getWidth(), h = getHeight(), r = h / 2;
			paint.setStyle(Paint.Style.FILL);
			paint.setColor(Color.WHITE);
			canvas.drawRoundRect(0, 0, w, h, r, r, paint);
			paint.setColor(GO);
			if (value > 0) canvas.drawRoundRect(0, 0, Math.max(h, w * value), h, r, r, paint);
			paint.setStyle(Paint.Style.STROKE);
			paint.setStrokeWidth(dp(getContext(), 2));
			paint.setColor(INK);
			canvas.drawRoundRect(1, 1, w - 1, h - 1, r, r, paint);
		}
	}

	/** The rings drawn over the camera's raw picture: dashed, green when the disc's edge is between them. */
	static void rings(Canvas canvas, float size, double near, double far, boolean good, Context context) {
		Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
		ring.setStyle(Paint.Style.STROKE);
		ring.setStrokeWidth(size / 90);
		ring.setColor(good ? GO : SUN);
		ring.setPathEffect(new DashPathEffect(new float[] {size / 26, size / 40}, 0));
		for (double r : new double[] {near, far}) canvas.drawCircle(size / 2f, size / 2f, (float) (r * size / 2), ring);
	}
}
