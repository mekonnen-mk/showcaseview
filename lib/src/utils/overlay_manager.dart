/*
 * Copyright (c) 2021 Simform Solutions
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/linked_showcase_data_model.dart';
import '../showcase/showcase_controller.dart';
import '../showcase/showcase_service.dart';
import '../showcase/showcase_view.dart';
import 'extensions.dart';
import 'shape_clipper.dart';

/// A singleton manager class responsible for displaying and controlling
/// overlays in the ShowcaseView.
///
/// This class manages the creation, display, and removal of overlays used by
/// the showcase system. It coordinates with [ShowcaseView] to control
/// overlay visibility and maintains the current showcase scope.
class OverlayManager {
  /// Private constructor for singleton implementation
  OverlayManager._();

  /// Singleton instance of the manager
  static final _instance = OverlayManager._();

  /// Public accessor for the singleton instance
  static OverlayManager get instance => _instance;

  /// The overlay state where entries will be inserted
  OverlayState? overlayState;

  /// Current overlay entry being displayed
  OverlayEntry? _overlayEntry;

  /// Flag to determine if overlay should be shown
  var _shouldShow = false;

  /// Flag to determine if we're dismissing with animation
  var _isDismissing = false;

  /// Flag to track if this is the first showcase in the sequence
  var _isInitialShowcaseInSequence = true;

  /// Callback to notify when target animation completes
  VoidCallback? _onTargetAnimationComplete;

  /// The current showcase scope identifier
  String get _currentScope => ShowcaseService.instance.currentScope;

  /// Returns whether an overlay is currently being displayed
  bool get _isShowing => _overlayEntry != null;

  /// Returns whether this is the first showcase in the current sequence
  ///
  /// This is used by controllers to determine if they should disable animations
  /// during transitions between showcase steps.
  bool get isInitialShowcaseInSequence => _isInitialShowcaseInSequence;

  /// Registers a callback to be notified when the target animation completes
  ///
  /// This is used by tooltips to delay their appearance until after the
  /// target morph animation finishes.
  void registerTargetAnimationCallback(VoidCallback callback) {
    _onTargetAnimationComplete = callback;
  }

  /// Clears the target animation completion callback
  void clearTargetAnimationCallback() {
    _onTargetAnimationComplete = null;
  }

  /// Updates the overlay visibility based on the provided showcase view.
  ///
  /// This method is called from showcase widgets to control overlay visibility.
  /// If the scope has changed, it will dispose the previous overlay.
  ///
  /// * [show] - Whether to show or hide the overlay.
  /// * [scope] - The new scope to be set as current.
  void update({
    required bool show,
    required String scope,
  }) {
    if (_currentScope != scope) {
      ShowcaseService.instance.updateCurrentScope(scope);
    }
    _shouldShow = show;
    _sync();
  }

  /// Updates the overlay state reference used by the manager
  ///
  /// This method allows setting or updating the [OverlayState] that will be
  /// used for inserting overlay entries.
  ///
  /// * [overlayState] - The new overlay state to use, can be null
  void updateState(OverlayState? overlayState) =>
      this.overlayState = overlayState;

  /// Disposes the overlay for the specified scope.
  ///
  /// Hides the overlay if it's currently showing and matches the provided
  /// scope.
  ///
  /// * [scope] - The scope to dispose overlays for
  Future<void> dispose({required String scope}) async {
    if (!_isShowing || _currentScope != scope) return;
    await _hideWithAnimation();
  }

  /// Shows the overlay using the provided builder.
  ///
  /// Creates a new overlay entry if none exists, otherwise rebuilds the
  /// existing one.
  void _show(WidgetBuilder overlayBuilder) {
    if (_overlayEntry != null) {
      // Rebuild overlay - not the initial showcase anymore
      _isInitialShowcaseInSequence = false;
      _rebuild();
      return;
    }
    // Create the overlay - this is the initial showcase
    _isInitialShowcaseInSequence = true;
    _overlayEntry = OverlayEntry(builder: overlayBuilder);
    overlayState?.insert(_overlayEntry!);
  }

  /// Removes and clears the current overlay entry immediately.
  void _hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // Reset the flag for next showcase sequence
    _isInitialShowcaseInSequence = true;
  }

  /// Removes the overlay with fade-out animation.
  Future<void> _hideWithAnimation() async {
    if (_overlayEntry == null) return;

    // Trigger fade-out animation in the overlay widget
    final context = _overlayEntry!.mounted ? _overlayEntry : null;
    if (context != null) {
      // Get the state and trigger fade-out
      await _triggerFadeOut();
    }

    _hide();
  }

  /// Triggers the fade-out animation by notifying the overlay state.
  Future<void> _triggerFadeOut() async {
    _isDismissing = true;
    _rebuild();
    // Wait for the fade-out animation to complete (500ms duration)
    await Future<void>.delayed(const Duration(milliseconds: 425)); // 500 * 0.85
    _isDismissing = false;
  }

  /// Synchronizes the overlay visibility with the showcase manager state.
  ///
  /// Shows or hides the overlay based on the [_shouldShow] flag.
  void _sync() {
    if (_isShowing && !_shouldShow) {
      // Hide with fade-out animation
      _hideWithAnimation();
    } else if (!_isShowing && _shouldShow) {
      _show(_getBuilder);
    } else {
      _rebuild();
    }
  }

  /// Creates and returns the overlay widget structure.
  ///
  /// Builds a stack with background and tooltip widgets based on active
  /// controllers.
  Widget _getBuilder(BuildContext context) {
    if (!context.mounted || !(_overlayEntry?.mounted ?? true)) {
      return const SizedBox.shrink();
    }

    final showcaseView = ShowcaseView.getNamed(_currentScope);
    final controllers = ShowcaseService.instance
            .getControllers(
              scope: showcaseView.scope,
            )[showcaseView.getActiveShowcaseKey]
            ?.values
            .toList() ??
        <ShowcaseController>[];

    if (controllers.isEmpty) return const SizedBox.shrink();

    return _ShowcaseOverlay(
      key: ValueKey(showcaseView.getActiveShowcaseKey),
      controllers: controllers,
      isDismissing: _isDismissing,
      isInitialShowcase: _isInitialShowcaseInSequence,
    );
  }

  /// Forces the overlay entry to rebuild
  void _rebuild() => _overlayEntry?.markNeedsBuild();
}

/// A private stateful widget that manages the animation and rendering of the
/// showcase overlay, including the animated "clear section".
class _ShowcaseOverlay extends StatefulWidget {
  const _ShowcaseOverlay({
    super.key,
    required this.controllers,
    this.isDismissing = false,
    this.isInitialShowcase = true,
  });

  final List<ShowcaseController> controllers;
  final bool isDismissing;
  final bool isInitialShowcase;

  @override
  State<_ShowcaseOverlay> createState() => _ShowcaseOverlayState();
}

class _ShowcaseOverlayState extends State<_ShowcaseOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late ShowcaseController _firstController;

  /// Stores the previous targets' data for morphing animation
  List<LinkedShowcaseDataModel>? _previousTargetsData;

  @override
  void initState() {
    super.initState();
    _firstController = widget.controllers.first;
    _animationController = AnimationController(
      vsync: this,
      duration: _getAnimationDuration(),
    );
    _animationController.addStatusListener(_onAnimationStatusChanged);
    _animationController.addListener(_onAnimationProgress);
    _animationController.forward();
  }

  /// Tracks animation progress to trigger tooltip before target completes
  bool _hasTriggeredTooltip = false;

  void _onAnimationProgress() {
    // Trigger tooltip at 90% (450ms of 500ms) to give it a head start
    if (!_hasTriggeredTooltip &&
        _animationController.value >= 0.9 &&
        !widget.isDismissing &&
        widget.isInitialShowcase) {
      _hasTriggeredTooltip = true;
      OverlayManager.instance._onTargetAnimationComplete?.call();
    }
  }

  /// Handles animation status changes to notify when target animation completes
  void _onAnimationStatusChanged(AnimationStatus status) {
    // Reset flag when animation completes or is reset
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _hasTriggeredTooltip = false;
    }
  }

  @override
  void didUpdateWidget(_ShowcaseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle dismissing animation
    if (!oldWidget.isDismissing && widget.isDismissing) {
      _animationController.reverse();
      return;
    }

    if (oldWidget.controllers.first != widget.controllers.first) {
      _previousTargetsData = _getCurrentTargetsData(oldWidget.controllers);
      _firstController = widget.controllers.first;
      _animationController
        ..duration = _getAnimationDuration()
        ..forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.removeStatusListener(_onAnimationStatusChanged);
    _animationController.removeListener(_onAnimationProgress);
    _animationController.dispose();
    super.dispose();
  }

  Duration _getAnimationDuration() {
    // Use longer duration for transitions to make morphing more graceful
    // Initial showcase: 500ms, Transitions: 700ms
    return widget.isInitialShowcase
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 700);
  }

  @override
  Widget build(BuildContext context) {
    final showcaseView = ShowcaseView.getNamed(
      ShowcaseService.instance.currentScope,
    );
    final currentShowcaseKey = showcaseView.getActiveShowcaseKey;
    final firstShowcaseConfig = _firstController.config;

    // Update controller data BEFORE we get animated data
    for (final controller in widget.controllers) {
      if (controller.key == currentShowcaseKey) {
        controller.updateControllerData();
      }
    }

    final backgroundContainer = ColoredBox(
      color: firstShowcaseConfig.overlayColor
          .reduceOpacity(firstShowcaseConfig.overlayOpacity),
      child: const Align(),
    );

    final overlayChild = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final animatedData =
            _getAnimatedLinkedShowcasesData(context, widget.controllers);

        final backgroundFadeAnimation = CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.0, 0.85, curve: Curves.easeIn),
        );

        final backgroundWidget = RepaintBoundary(
          child: GestureDetector(
            onTap: _firstController.handleBarrierTap,
            child: ClipPath(
              clipper: ShapeClipper(
                linkedObjectData: animatedData,
              ),
              child: ImageFiltered(
                enabled: _firstController.blur > 0.2,
                imageFilter: ImageFilter.blur(
                  sigmaX: _firstController.blur,
                  sigmaY: _firstController.blur,
                ),
                child: backgroundContainer,
              ),
            ),
          ),
        );

        return Stack(
          // This key is used to force rebuild the overlay when needed.
          // this key enables `_overlayEntry?.markNeedsBuild();` to detect that
          // output of the builder has changed.
          key: ValueKey(firstShowcaseConfig.hashCode),
          children: [
            // Fade in on initial showcase, and fade out when dismissing
            if (widget.isInitialShowcase || widget.isDismissing)
              FadeTransition(
                opacity: backgroundFadeAnimation,
                child: backgroundWidget,
              )
            else
              backgroundWidget,
            ...widget.controllers.expand((object) => object.tooltipWidgets),
          ],
        );
      },
    );

    final inheritedData = _firstController.inheritedData;

    // Wrap the child with captured themes to maintain the original context's
    // theme. Captured themes are used as to cover cases where there are
    // multiple themes in the widget tree.
    final themedChild = inheritedData.capturedThemes.wrap(overlayChild);

    // Wrap with other inherited widgets to maintain showcase's context's
    // inherited values.
    return Directionality(
      textDirection: inheritedData.textDirection,
      child: MediaQuery(
        data: inheritedData.mediaQuery,
        child: DefaultTextStyle(
          style: inheritedData.textStyle,
          child: themedChild,
        ),
      ),
    );
  }

  /// Extracts and returns animated linked showcase data from controllers.
  List<LinkedShowcaseDataModel> _getAnimatedLinkedShowcasesData(
    BuildContext context,
    List<ShowcaseController> controllers,
  ) {
    final controllerLength = controllers.length;
    final data = <LinkedShowcaseDataModel>[];

    final morphAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.15, 1.0, curve: Curves.fastOutSlowIn),
    );

    for (var i = 0; i < controllerLength; i++) {
      final model = controllers[i].linkedShowcaseDataModel;
      if (model != null) {
        final endRect = model.rect;
        final endRadius = model.radius;

        // Get previous model for morphing from previous position
        final previousModel =
            (_previousTargetsData != null && i < _previousTargetsData!.length)
                ? _previousTargetsData![i]
                : null;

        final beginRect = previousModel?.rect ?? endRect;

        final beginRadius = previousModel?.radius;

        final animatedRect = RectTween(
          begin: beginRect,
          end: endRect,
        ).evaluate(morphAnimation);

        final animatedRadius = BorderRadiusTween(
          begin: beginRadius,
          end: endRadius,
        ).evaluate(morphAnimation);

        data.add(
          model.copyWith(
            rect: controllers[i].isScrollRunning ? Rect.zero : animatedRect,
            radius: animatedRadius,
          ),
        );
      }
    }
    return data;
  }

  /// Extracts current targets data from controllers.
  List<LinkedShowcaseDataModel> _getCurrentTargetsData(
    List<ShowcaseController> controllers,
  ) {
    final data = <LinkedShowcaseDataModel>[];
    for (final controller in controllers) {
      if (controller.linkedShowcaseDataModel case final model?) {
        data.add(model);
      }
    }
    return data;
  }
}
