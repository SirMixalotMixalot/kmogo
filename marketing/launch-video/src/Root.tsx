import React from "react";
import { Composition } from "remotion";
import { LaunchVideo } from "./LaunchVideo";
import { DURATION, FPS } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <Composition id="RoamLaunch" component={LaunchVideo} durationInFrames={DURATION} fps={FPS} width={1080} height={1920} />
);
