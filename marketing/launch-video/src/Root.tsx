import React from "react";
import { Composition } from "remotion";
import { HeadlockVideo, headlock, MollyTalkVideo, mollyTalk } from "./cuts";
import { cutDuration } from "./LaunchVideo";
import { FPS } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="RoamLaunch" component={HeadlockVideo} durationInFrames={cutDuration(headlock)} fps={FPS} width={1080} height={1920} />
    <Composition id="RoamLaunchMollyTalk" component={MollyTalkVideo} durationInFrames={cutDuration(mollyTalk)} fps={FPS} width={1080} height={1920} />
  </>
);
