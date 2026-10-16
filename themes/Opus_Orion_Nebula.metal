// ============================================================================
// OPUS ORION NEBULA // themes/Opus_Orion_Nebula.metal
// Author: Claude Opus (Anthropic), 2026-10-16.
//
// The heart of the Orion Nebula (M42, the Huygens region, 0.68 x 0.57 pc), built from
// what telescopes measured of it and a model of the physics that makes it shine,
// fitted to those measurements. Seen from Earth it is the measured nebula; as the
// view swings a few degrees round it, the 3D shape behind that image appears.
//
// MEASURED (the shipped data, themes/Opus_Orion_Nebula.bin):
//  * Line brightness of Halpha, [O III] 5007, [N II] 6584, [S II] 6731 and [O I] 6300 over
//    the whole field, corrected for dust, and the dust reddening c(Hbeta) itself: VLT/MUSE,
//    Weilbacher et al. 2015, A&A 582, A114 (data doi:10.17876/data/2023_3, CC0).
//    Downsampled 3x to 0.6" texels and 8-bit log-encoded (encoding error < 1%), bright
//    stars masked, and the instrument's slicer stripes (1.5-3.7%) removed. Halpha is their
//    dereddened Hbeta x 2.89, the Case-B ratio they dereddened with.
//  * [S II] electron density, and the line-of-sight velocities of Halpha, [N II] and
//    [S II] from the same data (used by the fit, not shipped).
//  * Positions and V magnitudes of the 12 brightest stars in the field (SIMBAD), and
//    temperatures of the Trapezium stars (Simon-Diaz et al. 2006).
//  * The dust between us and Orion: Edenhofer et al. 2024 3D dust map (A&A 685, A82;
//    doi:10.5281/zenodo.8187943, CC BY 4.0), integrated toward M42 to 360 pc.
//
// FITTED (offline, tools/orion_bake/bake.py; numbers in its report):
//  * The ionisation front, the surface of the molecular cloud behind the nebula: a
//    smooth B-spline surface whose photoionisation balance with theta1 Ori C
//    (Q = 1.7e49 photons/s, O'Dell et al. 2009) and theta2 Ori A reproduces the
//    measured Halpha emission measure on scales above ~8" (residual 0.041 dex rms):
//    every patch of front is lit at its true angle and seen through at its true angle.
//    It lands 0.165 pc behind theta1 Ori C, which the fit never saw: Wen & O'Dell 1995
//    found 0.2 pc at their 440 pc, 0.18 pc at ours. It curves up toward us, a concave
//    bowl, tilted 23 deg (median) from the line of sight.
//  * The ionised gas: a photoevaporation flow off the front, isothermal and sonic at
//    the front (Henney, Arthur & Garcia-Diaz 2005), so density and speed fall and rise
//    with height. Its thickness comes from the measured emission measure and [S II]
//    density, with one clumping factor fitted so it matches the front's curvature: the
//    flow needs 2.1x the [S II] density, as the denser [Cl III] gas in the same data shows.
//  * Where each ion shines, from the measured velocities: the flow predicts that
//    Halpha leads [N II] by 6.3 km/s if [N II] comes from the front itself; the data
//    say 6.0 (per texel: rms 2.2 km/s). So [N II], [S II] and [O I] are drawn as a sheet
//    on the front, and Halpha and [O III] fill the flow. ([S II] is 1.1 km/s slower still:
//    it shines partly inside the accelerating front, which the sheet stands in for.)
//  * The dust in front: what Edenhofer's map puts before 360 pc (A_V 0.08) is a distant
//    screen; the rest, 93% of the measured reddening, is the Veil, 1 pc in front of the
//    Trapezium. (The same sightline shows the Orion cloud behind as a dust wall at
//    417-436 pc.)
//
// ASSUMED (stated, not measured):
//  * Distance 400 pc (388-414 pc measured). theta2 Ori A lies at theta1 Ori C's depth.
//  * Te = 9000 K everywhere; sound speed 11 km/s; the flow and the ion layers are
//    the same everywhere apart from their scale. [O III] fills the flow like Halpha
//    (O++ is the main ion above the thin N+ zone). Dust inside the ionised gas, and
//    light scattered by dust (Orion's blue continuum), are left out.
//  * The Veil is a thin screen 1 pc in front of theta1 Ori C (literature: 0.4-3 pc).
//  * Fainter cluster stars: positions and brightnesses are statistical, drawn from the
//    measured structure of the Orion Nebula Cluster (Da Rio et al. 2014: rho ~ r^-2.2,
//    core 0.2 pc, ellipticity 0.3) and the Kroupa 2001 mass function, with rough 1 Myr
//    pre-main-sequence luminosities and blackbody spectra. Only the 12 bright stars are real.
//  * Camera: orthographic (we are 400 pc away), an exposure, an asinh stretch and a soft
//    star image (a telescope's, not an eye's). It starts on Earth's line of sight, where
//    it shows the measured maps (median 0.3/255 of a display level off them, 99% within
//    1.2/255: tools/orion_bake/verify_earth_view.py), then swings slowly up to 4.3 deg
//    round the nebula and back, every 16 minutes. Off Earth's line of sight what you see
//    is the fitted geometry, not more data; its least certain part is the flow's
//    thickness (tools/orion_bake/README.md).
//
// COLOUR: each emission line is its own wavelength (NIST, in air) through the CIE 1931
// colour matching functions (Wyman, Sloan & Shirley 2013 fit), with the doublet and
// Balmer partners at their theoretical ratios (Storey & Zeippen 2000; Storey & Hummer
// 1995; the [S II] doublet ratio from the measured density, Sanders et al. 2016) and
// each line dimmed by the Veil by its own extinction (Blagrave et al. 2007, R_V = 5.5).
// Lines are purer than a screen can show; colours outside sRGB keep their luminance and hue
// and are compressed in saturation toward the sRGB boundary (the [O III]-lit core is far
// outside it: CIE x ~ 0.08, y ~ 0.44). PALETTE = 1 shows instead the Hubble "SHO" false-colour mapping
// ([S II] red, Halpha green, [O III] blue): labelled, not true colour, but it shows the
// filaments the [O III] glow washes out.
//
// How it runs: argus_init decodes the data file into a 588 x 1477 state (three blocks:
// the flow lines, the front sheet, the front's normal; and one row: the flow's profile). argus_draw finds where each
// pixel's ray meets the front (coarse march + bisection), integrates the flow emission
// between the front and the camera exactly per segment (the flow's emission profile is
// a tabulated CDF), adds the front sheet seen at its angle, dims by the Veil and the
// ISM, and adds stars culled per 32x32 tile. No argus_step: the state never changes.
//
// @argus state 588x1477
// @argus data Opus_Orion_Nebula.bin 588x984 rgba8
// ============================================================================

constant int   PALETTE   = 0;        // 0 = true colour, 1 = Hubble SHO false colour (labelled)
constant float D_VEIL    = 1.0f;     // pc in front of theta1 Ori C (O'Dell et al. 2009)
constant float VIEW_W_PC = 0.60f;    // field of view across the screen's width...
constant float VIEW_H_PC = 0.50f;    // ...or its height, whichever is tighter (the data are 0.68 x 0.57 pc)
constant float2 VIEW_C   = float2(-0.035f, -0.045f);   // view centre, pc from theta1 Ori C (west, north)
constant float ORBIT_YAW = 0.075f;   // radians (4.3 deg)
constant float ORBIT_PITCH = 0.045f; // radians (2.6 deg)
constant float ORBIT_T   = 480.0f;   // seconds per yaw swing; pitch takes twice as long
constant float PIVOT_Z   = -0.12f;   // the orbit turns about this depth (pc): the front stays put
constant float GRAZE_MAX = 4.0f;     // front-sheet brightening at grazing view (a sheet is not infinitely thin)

// BEGIN BAKED (tools/orion_bake/bake.py writes this block; do not edit by hand)
constant uint DATA_W = 588u, DATA_H = 492u;          // one block; the file holds two
constant float TEXEL_PC = 0.0011636f;                     // texel size at 400 pc
constant float DIST_PC = 400.0f;
constant float EXPOSURE = 8.70245f;                   // chosen: Earth-view p99.95 luminance = white
constant float STRETCH = 0.241322f;                     // chosen: asinh knee at 2.5 x the median luminance
constant float3 SHO_NORM = float3(0.00892226f, 0.197712f, 0.181103f);   // Hubble palette channel scales
constant float3 STAR_K = float3(0.8466f, 0.9025f, 1.0590f);   // A/A_Hb for star light in X, Y, Z
constant float2 STAR_C_TEX = float2(307.584f, 279.662f);   // theta1 Ori C, texels from the west-south corner
constant float FLOW_G = 0.120984f;
constant float FRONT_ZMIN = -0.3543f, FRONT_ZMAX = -0.1233f;   // pc, over the field
constant float2 LOG_RANGE[6] = {  // log10 of erg/s/cm^2/sr: Halpha, [O III], [N II], [S II] 6731, [O I] 6300, R0 (pc)
    float2(-2.00078f, -0.01853f), float2(-2.26041f, 0.07867f), float2(-2.70475f, -0.69159f), float2(-3.53663f, -1.64013f), float2(-4.28018f, -2.07072f), float2(-2.30103f, 0.17609f)};
constant float C_FG = 0.0393f;              // c(Hb) of the diffuse ISM in front (Edenhofer+2024)
constant float FRONT_P[13][15] = {          // B-spline control points: front depth z (pc, toward us = +)
    {-0.23275f, -0.21952f, -0.20818f, -0.19814f, -0.18599f, -0.17377f, -0.15902f, -0.14973f, -0.15718f, -0.16640f, -0.17555f, -0.19729f, -0.22743f, -0.26227f, -0.29763f},
    {-0.22373f, -0.21605f, -0.20793f, -0.19668f, -0.17980f, -0.17038f, -0.16029f, -0.14315f, -0.14100f, -0.15879f, -0.17919f, -0.20665f, -0.23629f, -0.27037f, -0.30190f},
    {-0.21197f, -0.20854f, -0.20133f, -0.18695f, -0.17124f, -0.16291f, -0.14669f, -0.13563f, -0.13583f, -0.15977f, -0.18576f, -0.21675f, -0.24711f, -0.27705f, -0.30586f},
    {-0.19611f, -0.19479f, -0.18621f, -0.17196f, -0.15704f, -0.14486f, -0.13912f, -0.15290f, -0.15711f, -0.17241f, -0.20132f, -0.22938f, -0.25697f, -0.28522f, -0.31440f},
    {-0.18213f, -0.18337f, -0.17405f, -0.15533f, -0.13434f, -0.14798f, -0.17344f, -0.17934f, -0.17729f, -0.19199f, -0.21791f, -0.24545f, -0.26908f, -0.30027f, -0.32893f},
    {-0.18280f, -0.17692f, -0.16560f, -0.14928f, -0.16418f, -0.19126f, -0.18928f, -0.17199f, -0.16351f, -0.18482f, -0.20689f, -0.23805f, -0.27426f, -0.30707f, -0.33473f},
    {-0.22086f, -0.20760f, -0.20086f, -0.20774f, -0.21896f, -0.21652f, -0.18743f, -0.16574f, -0.15285f, -0.16936f, -0.19625f, -0.23634f, -0.27178f, -0.29900f, -0.32938f},
    {-0.29701f, -0.29430f, -0.27256f, -0.26887f, -0.23448f, -0.21426f, -0.18389f, -0.16963f, -0.15810f, -0.15962f, -0.18387f, -0.22789f, -0.26461f, -0.29567f, -0.32421f},
    {-0.36173f, -0.35859f, -0.32724f, -0.30524f, -0.24447f, -0.21348f, -0.19472f, -0.17454f, -0.16393f, -0.16229f, -0.18015f, -0.20819f, -0.24364f, -0.28042f, -0.31346f},
    {-0.38754f, -0.35861f, -0.32460f, -0.28187f, -0.23561f, -0.19058f, -0.17476f, -0.15909f, -0.15642f, -0.16322f, -0.17673f, -0.19916f, -0.22459f, -0.25923f, -0.29480f},
    {-0.38115f, -0.33140f, -0.27158f, -0.21471f, -0.17715f, -0.14518f, -0.13692f, -0.14070f, -0.14821f, -0.15995f, -0.17409f, -0.19544f, -0.21667f, -0.24220f, -0.27346f},
    {-0.34311f, -0.28235f, -0.21659f, -0.15353f, -0.12829f, -0.12142f, -0.12209f, -0.13053f, -0.14061f, -0.15212f, -0.16462f, -0.18322f, -0.20666f, -0.23199f, -0.25786f},
    {-0.29697f, -0.22724f, -0.16291f, -0.11202f, -0.09408f, -0.10232f, -0.11483f, -0.12396f, -0.13300f, -0.14545f, -0.15919f, -0.17731f, -0.20032f, -0.22328f, -0.24452f},
};
constant float FLOW_CDF[64] = {   // share of a flow line's emission below h = 3 R0 i / 63
    0.000000f, 0.249360f, 0.405022f, 0.516257f, 0.599780f, 0.664430f, 0.715574f, 0.756722f, 0.790287f, 0.817987f, 0.841075f, 0.860489f, 0.876940f, 0.890979f, 0.903035f, 0.913449f, 0.922491f, 0.930381f, 0.937296f, 0.943383f, 0.948762f, 0.953533f, 0.957778f, 0.961569f, 0.964964f, 0.968013f, 0.970759f, 0.973238f, 0.975482f, 0.977519f, 0.979370f, 0.981057f, 0.982598f, 0.984007f, 0.985299f, 0.986485f, 0.987575f, 0.988580f, 0.989508f, 0.990364f, 0.991157f, 0.991892f, 0.992574f, 0.993208f, 0.993797f, 0.994346f, 0.994859f, 0.995337f, 0.995784f, 0.996202f, 0.996594f, 0.996961f, 0.997305f, 0.997629f, 0.997934f, 0.998220f, 0.998490f, 0.998744f, 0.998984f, 0.999211f, 0.999425f, 0.999627f, 0.999819f, 1.000000f};
constant float FLOW_PDF[64] = {   // d CDF / d(h/R0)
    8.265542f, 3.943970f, 2.721009f, 2.005095f, 1.532569f, 1.201009f, 0.959061f, 0.777476f, 0.638207f, 0.529513f, 0.443434f, 0.374411f, 0.318460f, 0.272671f, 0.234874f, 0.203435f, 0.177098f, 0.154895f, 0.136066f, 0.120010f, 0.106250f, 0.094402f, 0.084155f, 0.075256f, 0.067498f, 0.060709f, 0.054748f, 0.049497f, 0.044857f, 0.040744f, 0.037089f, 0.033832f, 0.030922f, 0.028316f, 0.025976f, 0.023872f, 0.021974f, 0.020260f, 0.018709f, 0.017301f, 0.016023f, 0.014859f, 0.013798f, 0.012830f, 0.011944f, 0.011132f, 0.010388f, 0.009704f, 0.009075f, 0.008496f, 0.007962f, 0.007468f, 0.007012f, 0.006590f, 0.006199f, 0.005836f, 0.005499f, 0.005186f, 0.004895f, 0.004623f, 0.004370f, 0.004134f, 0.003913f, 0.003707f};
struct Line { float3 xyz; float ratio; float k; };  // CIE XYZ per unit energy, ratio to the mapped line, A/A_Hb
constant Line L_BALMER[4] = {
    {float3(0.20082f, 0.07973f, 0.00000f), 1.00000f, 0.7800f},   // 656.282 nm
    {float3(0.05445f, 0.18025f, 0.57808f), 0.34602f, 1.0000f},   // 486.133 nm
    {float3(0.31971f, 0.01324f, 1.60916f), 0.16215f, 1.0860f},   // 434.047 nm
    {float3(0.05007f, 0.00269f, 0.20862f), 0.08969f, 1.1170f},   // 410.174 nm
};
constant Line L_OIII[2] = {
    {float3(0.00191f, 0.33727f, 0.26165f), 1.00000f, 0.9780f},   // 500.684 nm
    {float3(0.00893f, 0.27372f, 0.33841f), 0.33557f, 0.9850f},   // 495.891 nm
};
constant Line L_NII[2] = {
    {float3(0.17749f, 0.07132f, 0.00000f), 1.00000f, 0.7780f},   // 658.345 nm
    {float3(0.21878f, 0.08622f, 0.00000f), 0.32787f, 0.7818f},   // 654.805 nm
};
constant Line L_SII[2] = {
    {float3(0.06460f, 0.02984f, 0.00000f), 1.00000f, 0.7605f},   // 673.082 nm
    {float3(0.07200f, 0.03268f, 0.00000f), -1.00000f, 0.7622f},   // 671.644 nm
};
constant Line L_OI[2] = {
    {float3(0.65639f, 0.26360f, 0.00000f), 1.00000f, 0.8108f},   // 630.030 nm
    {float3(0.52644f, 0.20497f, 0.00000f), 0.33367f, 0.8034f},   // 636.378 nm
};
constant float A_V_PER_A_HB = 0.9097f;   // CCM89 R_V = 5.5
constant uint N_STARS = 569u;
constant float4 STARS[N_STARS] = {   // x, y, z (pc from theta1 Ori C: west, north, toward us); first 12 real
    float4(0.0000f, 0.0000f, 0.0000f, 0),  // theta1 Ori C float4(-0.2877f, -0.1898f, 0.0000f, 0),  // theta2 Ori B float4(-0.1864f, -0.1841f, 0.0000f, 0),  // theta2 Ori A float4(-0.0229f, 0.0123f, 0.0000f, 0),  // theta1 Ori D
    float4(0.0186f, 0.0167f, 0.0000f, 0),  // theta1 Ori A float4(0.0096f, 0.0313f, 0.0000f, 0),  // theta1 Ori B float4(-0.3463f, -0.3441f, 0.0000f, 0),  // V1073 Ori float4(-0.1232f, 0.1912f, 0.0000f, 0),  // V1230 Ori
    float4(-0.0076f, -0.0044f, 0.0000f, 0),  // theta1 Ori F float4(0.4731f, -0.2197f, 0.0000f, 0),  // KS Ori float4(-0.0148f, 0.1892f, 0.0000f, 0),  // MR Ori float4(0.3136f, -0.2261f, 0.0000f, 0),  // LL Ori
    float4(-0.3911f, 0.0676f, 0.6167f, 0), float4(0.1671f, -0.1100f, 0.3654f, 0), float4(-0.0522f, -0.0127f, 0.2342f, 0), float4(0.0758f, 0.0658f, 0.0828f, 0),
    float4(-0.0906f, 0.0942f, 0.5716f, 0), float4(0.0944f, 0.1172f, -0.4308f, 0), float4(0.1699f, -0.1446f, -0.2276f, 0), float4(-0.0143f, -0.0069f, -0.0639f, 0),
    float4(-0.0162f, -0.0080f, 0.6516f, 0), float4(0.2253f, -0.2085f, 0.2220f, 0), float4(-0.3101f, 0.1619f, -0.1280f, 0), float4(-0.2098f, -0.1273f, -0.6002f, 0),
    float4(-0.1491f, 0.0254f, 0.1037f, 0), float4(-0.1208f, 0.1280f, -0.0224f, 0), float4(-0.0327f, 0.1931f, -0.1874f, 0), float4(0.0588f, 0.1291f, 0.0418f, 0),
    float4(-0.3099f, -0.2404f, 0.0014f, 0), float4(0.2311f, -0.0888f, -0.1973f, 0), float4(-0.0983f, -0.1875f, -0.2114f, 0), float4(0.1768f, -0.2469f, -0.1290f, 0),
    float4(-0.3478f, -0.1630f, -0.0076f, 0), float4(-0.0716f, 0.1066f, 0.0252f, 0), float4(-0.1787f, -0.2210f, -0.3428f, 0), float4(-0.1251f, -0.0333f, -0.4108f, 0),
    float4(0.2782f, 0.1817f, 0.1827f, 0), float4(-0.2971f, 0.0609f, 0.1529f, 0), float4(0.0214f, 0.1141f, 0.1782f, 0), float4(0.0788f, 0.1959f, -0.3561f, 0),
    float4(-0.2759f, 0.0797f, 0.2033f, 0), float4(0.0050f, -0.0004f, 0.7949f, 0), float4(-0.0526f, 0.1965f, 0.0442f, 0), float4(0.2043f, 0.1083f, -0.1042f, 0),
    float4(0.2715f, -0.1265f, -0.1056f, 0), float4(-0.0681f, -0.0203f, 0.1656f, 0), float4(-0.0413f, -0.2478f, 0.1717f, 0), float4(-0.0824f, -0.0483f, -0.3143f, 0),
    float4(-0.3304f, -0.0414f, -0.0996f, 0), float4(0.0350f, -0.2080f, 0.0261f, 0), float4(-0.0171f, 0.2069f, 0.6407f, 0), float4(0.0086f, 0.1962f, 0.0920f, 0),
    float4(0.2606f, 0.1303f, 0.0227f, 0), float4(-0.0854f, 0.1307f, 0.0147f, 0), float4(0.1550f, 0.0540f, 0.6644f, 0), float4(-0.1625f, -0.1653f, 0.1253f, 0),
    float4(-0.0110f, 0.0888f, -0.2006f, 0), float4(-0.2699f, 0.0018f, -0.2960f, 0), float4(0.2896f, -0.1502f, -0.4341f, 0), float4(0.2526f, 0.1648f, -0.0436f, 0),
    float4(-0.0596f, -0.2557f, 0.3389f, 0), float4(-0.3467f, 0.0429f, 0.0433f, 0), float4(-0.1484f, -0.1828f, 0.2914f, 0), float4(-0.0426f, 0.1276f, 0.0211f, 0),
    float4(0.2610f, -0.1913f, 0.6327f, 0), float4(-0.2616f, 0.1084f, -0.5341f, 0), float4(-0.3859f, -0.1931f, 0.3101f, 0), float4(0.0297f, 0.1906f, -0.6675f, 0),
    float4(-0.0633f, 0.1322f, 0.0476f, 0), float4(-0.3627f, -0.2754f, -0.6158f, 0), float4(-0.1961f, 0.0852f, -0.6162f, 0), float4(-0.1064f, -0.0962f, -0.1687f, 0),
    float4(-0.1118f, -0.1753f, 0.1278f, 0), float4(-0.3438f, 0.0965f, -0.0616f, 0), float4(0.0253f, -0.0563f, 0.0517f, 0), float4(-0.3002f, 0.1107f, -0.4204f, 0),
    float4(-0.0703f, -0.2733f, 0.4895f, 0), float4(-0.1326f, 0.1544f, 0.2384f, 0), float4(0.0721f, 0.0793f, -0.1919f, 0), float4(-0.0794f, 0.1165f, -0.2979f, 0),
    float4(0.3052f, -0.0313f, -0.6348f, 0), float4(0.1463f, -0.1922f, 0.0209f, 0), float4(0.0875f, -0.0531f, -0.1517f, 0), float4(0.3000f, 0.1424f, 0.0869f, 0),
    float4(-0.0919f, 0.1618f, -0.2217f, 0), float4(0.1041f, 0.1491f, -0.1246f, 0), float4(0.0734f, -0.0326f, 0.4462f, 0), float4(0.2981f, -0.0882f, 0.3906f, 0),
    float4(0.1092f, -0.1333f, -0.4370f, 0), float4(-0.1366f, -0.0988f, 0.0347f, 0), float4(0.1156f, -0.1428f, -0.5316f, 0), float4(-0.1883f, 0.2054f, 0.2069f, 0),
    float4(0.0224f, -0.1639f, 0.1699f, 0), float4(-0.1238f, 0.1502f, -0.3070f, 0), float4(-0.2320f, -0.1868f, -0.0447f, 0), float4(0.2721f, 0.1333f, -0.0836f, 0),
    float4(0.2439f, -0.0599f, -0.2418f, 0), float4(0.0500f, 0.0118f, -0.6009f, 0), float4(0.0441f, -0.0532f, -0.0119f, 0), float4(0.2127f, 0.0612f, 0.0208f, 0),
    float4(0.0231f, -0.0456f, 0.3790f, 0), float4(0.0983f, 0.2095f, -0.4972f, 0), float4(-0.3888f, 0.1413f, -0.7820f, 0), float4(0.2708f, 0.1834f, -0.4071f, 0),
    float4(-0.0479f, 0.1420f, -0.0570f, 0), float4(-0.3573f, 0.1595f, 0.7760f, 0), float4(0.2175f, 0.1957f, 0.0188f, 0), float4(-0.0917f, 0.1645f, -0.1757f, 0),
    float4(-0.0421f, -0.2286f, -0.0786f, 0), float4(0.0886f, -0.2580f, 0.1600f, 0), float4(-0.1823f, -0.1549f, -0.0799f, 0), float4(-0.0371f, -0.2223f, 0.0728f, 0),
    float4(0.0575f, -0.1348f, -0.0209f, 0), float4(0.2401f, -0.2382f, -0.3237f, 0), float4(-0.0379f, -0.2352f, 0.1274f, 0), float4(-0.1493f, 0.0164f, 0.0042f, 0),
    float4(0.0123f, -0.3035f, 0.3206f, 0), float4(0.2177f, -0.1601f, -0.3430f, 0), float4(-0.0437f, -0.0324f, 0.0038f, 0), float4(-0.1353f, 0.1466f, -0.0954f, 0),
    float4(0.0985f, 0.1231f, -0.1435f, 0), float4(0.1657f, -0.2605f, 0.5396f, 0), float4(-0.0661f, 0.0892f, -0.4487f, 0), float4(0.2963f, 0.0043f, 0.1683f, 0),
    float4(0.1309f, -0.0686f, -0.1902f, 0), float4(-0.2562f, 0.1950f, 0.1114f, 0), float4(-0.1658f, -0.1432f, -0.5130f, 0), float4(-0.1809f, -0.0790f, -0.6813f, 0),
    float4(0.2374f, 0.0213f, -0.0778f, 0), float4(-0.1366f, -0.2050f, -0.2852f, 0), float4(0.0898f, 0.0926f, 0.1550f, 0), float4(-0.0007f, 0.0317f, 0.0065f, 0),
    float4(-0.2682f, -0.1985f, -0.0956f, 0), float4(-0.0085f, -0.2471f, -0.5521f, 0), float4(-0.3275f, -0.2148f, -0.4284f, 0), float4(0.2554f, 0.1005f, 0.1241f, 0),
    float4(-0.0606f, 0.1803f, -0.2964f, 0), float4(0.0544f, 0.0889f, -0.4180f, 0), float4(0.0749f, -0.0970f, -0.2159f, 0), float4(-0.0152f, 0.1207f, -0.0938f, 0),
    float4(0.1040f, 0.0525f, 0.1547f, 0), float4(-0.0462f, 0.1872f, -0.1117f, 0), float4(-0.2152f, 0.0359f, 0.1753f, 0), float4(-0.2696f, 0.2068f, -0.1701f, 0),
    float4(0.0280f, 0.0609f, 0.3636f, 0), float4(-0.0935f, -0.2673f, 0.4653f, 0), float4(0.0630f, -0.1248f, 0.7520f, 0), float4(0.0263f, 0.0823f, -0.0824f, 0),
    float4(0.0791f, 0.1915f, -0.1996f, 0), float4(-0.2887f, -0.2888f, -0.1128f, 0), float4(-0.0056f, -0.2862f, -0.5712f, 0), float4(0.2520f, -0.2032f, 0.2443f, 0),
    float4(-0.1210f, -0.1726f, 0.1048f, 0), float4(0.0117f, 0.0715f, -0.3834f, 0), float4(-0.1312f, -0.2175f, -0.3447f, 0), float4(-0.1238f, 0.1704f, 0.1528f, 0),
    float4(0.2828f, 0.0530f, 0.2771f, 0), float4(0.0254f, 0.2026f, -0.0941f, 0), float4(-0.0285f, -0.1429f, 0.7596f, 0), float4(-0.1314f, -0.0488f, 0.2214f, 0),
    float4(-0.2869f, -0.2608f, 0.5929f, 0), float4(-0.0995f, 0.0555f, 0.0804f, 0), float4(-0.2083f, 0.1569f, -0.0591f, 0), float4(-0.2041f, 0.0711f, 0.5065f, 0),
    float4(0.0541f, 0.2065f, 0.3323f, 0), float4(0.0945f, -0.1115f, -0.0832f, 0), float4(-0.2244f, 0.1592f, -0.1995f, 0), float4(0.3204f, -0.1905f, -0.2473f, 0),
    float4(0.1155f, -0.2984f, 0.1210f, 0), float4(0.0687f, 0.0617f, -0.1852f, 0), float4(0.2071f, -0.1530f, 0.4037f, 0), float4(0.2331f, -0.2653f, -0.5642f, 0),
    float4(-0.0884f, -0.0034f, -0.3924f, 0), float4(0.2200f, -0.1292f, -0.0800f, 0), float4(0.0490f, 0.1309f, 0.1886f, 0), float4(-0.3024f, 0.0708f, -0.2952f, 0),
    float4(0.2348f, -0.1474f, 0.6444f, 0), float4(-0.0772f, 0.1133f, -0.2063f, 0), float4(-0.3383f, 0.1590f, 0.1855f, 0), float4(-0.1679f, -0.0747f, -0.0965f, 0),
    float4(-0.0633f, -0.0336f, 0.2309f, 0), float4(-0.2784f, -0.2531f, -0.3388f, 0), float4(0.0746f, 0.1386f, -0.5796f, 0), float4(-0.2187f, -0.1704f, 0.1508f, 0),
    float4(0.0250f, 0.0253f, -0.0963f, 0), float4(0.2119f, 0.1898f, -0.6413f, 0), float4(-0.0741f, -0.2663f, -0.1682f, 0), float4(0.0970f, 0.0812f, 0.1752f, 0),
    float4(-0.0343f, -0.0116f, 0.0439f, 0), float4(-0.2609f, 0.1425f, 0.2805f, 0), float4(0.0193f, -0.1642f, 0.0836f, 0), float4(-0.2730f, -0.1672f, 0.2499f, 0),
    float4(0.1357f, 0.1975f, 0.7626f, 0), float4(0.1753f, 0.1166f, -0.1453f, 0), float4(-0.3012f, 0.0683f, 0.2789f, 0), float4(0.2167f, 0.0612f, 0.1489f, 0),
    float4(-0.0999f, -0.2009f, -0.1193f, 0), float4(-0.1315f, -0.1067f, -0.0746f, 0), float4(0.2646f, -0.2667f, 0.1366f, 0), float4(-0.3388f, 0.0338f, -0.3847f, 0),
    float4(-0.1290f, -0.0932f, 0.0365f, 0), float4(0.1010f, -0.0292f, -0.2775f, 0), float4(0.1887f, 0.0181f, -0.0687f, 0), float4(-0.1119f, -0.0867f, -0.1201f, 0),
    float4(-0.0802f, 0.2092f, 0.2157f, 0), float4(-0.2904f, 0.1764f, 0.3147f, 0), float4(-0.0179f, 0.1110f, 0.5236f, 0), float4(-0.0347f, -0.2818f, 0.0270f, 0),
    float4(-0.3780f, 0.0198f, 0.0675f, 0), float4(-0.2045f, 0.1278f, -0.1647f, 0), float4(-0.0378f, 0.1928f, 0.1761f, 0), float4(-0.0936f, -0.2038f, 0.0185f, 0),
    float4(0.1401f, -0.1878f, -0.0335f, 0), float4(-0.2128f, -0.0184f, -0.2486f, 0), float4(0.0579f, 0.0529f, 0.2103f, 0), float4(-0.1276f, 0.1634f, -0.2139f, 0),
    float4(0.0478f, 0.1876f, -0.0438f, 0), float4(0.2608f, 0.0360f, 0.2739f, 0), float4(-0.1436f, -0.0389f, -0.0911f, 0), float4(-0.0937f, 0.1002f, -0.6210f, 0),
    float4(0.1552f, -0.1740f, 0.1630f, 0), float4(-0.0870f, -0.1138f, 0.4736f, 0), float4(-0.1162f, 0.0572f, 0.3258f, 0), float4(-0.0550f, -0.0539f, 0.2130f, 0),
    float4(0.0447f, 0.1480f, -0.0097f, 0), float4(0.1977f, -0.0506f, -0.2010f, 0), float4(0.1086f, -0.1238f, 0.2554f, 0), float4(0.0445f, -0.2065f, -0.1036f, 0),
    float4(-0.2289f, 0.0408f, -0.4272f, 0), float4(0.0970f, 0.1543f, -0.0332f, 0), float4(-0.3352f, 0.0044f, -0.3282f, 0), float4(-0.0074f, -0.0412f, 0.0257f, 0),
    float4(0.0140f, -0.1356f, 0.0884f, 0), float4(-0.1201f, -0.0244f, 0.0066f, 0), float4(-0.1391f, -0.3039f, -0.4161f, 0), float4(-0.3513f, -0.2243f, 0.2580f, 0),
    float4(0.1567f, 0.0658f, 0.6675f, 0), float4(0.2156f, -0.2259f, 0.2662f, 0), float4(0.2661f, 0.1221f, -0.0187f, 0), float4(-0.2756f, -0.1337f, -0.2561f, 0),
    float4(0.1991f, 0.1366f, -0.0252f, 0), float4(-0.3744f, -0.0873f, -0.1992f, 0), float4(0.2803f, 0.1896f, 0.2141f, 0), float4(0.2285f, 0.2035f, 0.0531f, 0),
    float4(-0.2597f, -0.2190f, 0.5698f, 0), float4(-0.0335f, 0.1187f, 0.1177f, 0), float4(0.0095f, -0.1829f, 0.4040f, 0), float4(-0.0030f, -0.0458f, -0.6396f, 0),
    float4(-0.0228f, -0.0867f, 0.0186f, 0), float4(0.0028f, -0.1501f, -0.3629f, 0), float4(-0.1981f, -0.2728f, 0.4511f, 0), float4(0.1269f, 0.0280f, 0.1958f, 0),
    float4(0.0456f, 0.1072f, -0.2010f, 0), float4(0.0582f, 0.1804f, 0.3460f, 0), float4(0.0416f, -0.2161f, -0.0521f, 0), float4(0.0300f, 0.0789f, 0.1173f, 0),
    float4(0.1225f, -0.0946f, 0.2436f, 0), float4(0.0271f, 0.0604f, -0.3742f, 0), float4(0.2354f, -0.1216f, 0.2590f, 0), float4(0.0606f, 0.1252f, 0.1235f, 0),
    float4(-0.2691f, 0.0809f, 0.0638f, 0), float4(-0.1768f, -0.2479f, 0.4403f, 0), float4(0.2155f, -0.0167f, -0.1325f, 0), float4(-0.2503f, -0.1768f, -0.1844f, 0),
    float4(-0.2963f, -0.0630f, 0.0463f, 0), float4(0.0178f, -0.0258f, -0.1076f, 0), float4(0.1500f, 0.0022f, -0.2645f, 0), float4(0.1526f, -0.0430f, 0.6609f, 0),
    float4(0.2947f, -0.0784f, -0.1183f, 0), float4(-0.0962f, 0.1222f, -0.0645f, 0), float4(0.0118f, -0.2426f, -0.4354f, 0), float4(0.2958f, -0.0935f, 0.4939f, 0),
    float4(0.1463f, -0.0447f, -0.0112f, 0), float4(-0.0700f, -0.2269f, -0.6973f, 0), float4(-0.0649f, 0.1918f, 0.1483f, 0), float4(-0.2360f, 0.1385f, -0.1467f, 0),
    float4(0.0760f, -0.2254f, 0.1429f, 0), float4(0.3067f, 0.0213f, -0.4715f, 0), float4(0.0091f, -0.2881f, -0.2216f, 0), float4(-0.0601f, -0.0906f, -0.1532f, 0),
    float4(0.3036f, -0.1053f, -0.0924f, 0), float4(-0.1626f, -0.1197f, -0.0416f, 0), float4(-0.0293f, -0.0781f, -0.0760f, 0), float4(-0.2138f, -0.2591f, 0.6902f, 0),
    float4(-0.1168f, -0.1793f, -0.2042f, 0), float4(-0.1322f, 0.1193f, -0.2674f, 0), float4(-0.2879f, 0.1625f, 0.2355f, 0), float4(0.0733f, -0.2412f, -0.0433f, 0),
    float4(-0.2912f, -0.2440f, -0.0515f, 0), float4(0.2254f, -0.0198f, -0.0772f, 0), float4(-0.0194f, 0.1145f, 0.0830f, 0), float4(0.0157f, 0.1279f, -0.2959f, 0),
    float4(-0.1344f, 0.0086f, 0.7986f, 0), float4(-0.1281f, 0.0308f, -0.0757f, 0), float4(0.2927f, -0.0800f, -0.4844f, 0), float4(-0.0812f, 0.2001f, 0.2056f, 0),
    float4(0.2145f, 0.1342f, -0.4475f, 0), float4(0.2512f, -0.0062f, 0.3424f, 0), float4(-0.1157f, 0.1159f, 0.4525f, 0), float4(-0.2295f, -0.2749f, 0.4519f, 0),
    float4(0.2333f, 0.0270f, 0.2615f, 0), float4(0.1434f, 0.0228f, 0.0784f, 0), float4(-0.0392f, 0.0608f, -0.3721f, 0), float4(0.0799f, -0.2246f, -0.3184f, 0),
    float4(-0.1694f, 0.0877f, -0.2558f, 0), float4(-0.3832f, -0.2582f, -0.4082f, 0), float4(-0.0373f, 0.0327f, -0.4820f, 0), float4(0.0863f, 0.1712f, -0.1893f, 0),
    float4(-0.2332f, -0.1656f, -0.3475f, 0), float4(-0.0888f, -0.1948f, -0.3023f, 0), float4(0.0361f, -0.1872f, -0.4164f, 0), float4(0.0955f, 0.0083f, 0.0837f, 0),
    float4(-0.1535f, 0.1079f, 0.1747f, 0), float4(0.0089f, 0.1733f, -0.2182f, 0), float4(-0.0363f, 0.1141f, 0.2663f, 0), float4(0.1740f, -0.1279f, 0.2235f, 0),
    float4(-0.2253f, 0.1812f, -0.4023f, 0), float4(-0.1016f, -0.2533f, -0.4095f, 0), float4(0.1417f, 0.1999f, 0.6534f, 0), float4(0.0765f, 0.1179f, -0.2834f, 0),
    float4(0.0281f, -0.0491f, 0.0964f, 0), float4(-0.1906f, -0.1490f, -0.3092f, 0), float4(-0.0391f, -0.3047f, 0.2249f, 0), float4(0.1687f, -0.1638f, -0.4538f, 0),
    float4(0.0609f, -0.2127f, 0.2715f, 0), float4(0.0937f, 0.1238f, -0.1273f, 0), float4(0.0342f, -0.2404f, -0.1905f, 0), float4(0.2189f, -0.1447f, -0.0595f, 0),
    float4(0.2866f, -0.2132f, 0.4355f, 0), float4(-0.1891f, 0.2117f, -0.1624f, 0), float4(-0.3346f, -0.1699f, -0.7964f, 0), float4(0.1101f, 0.1583f, -0.0865f, 0),
    float4(0.1649f, 0.0926f, -0.1318f, 0), float4(-0.1582f, 0.2129f, -0.0211f, 0), float4(-0.0273f, 0.1914f, -0.0934f, 0), float4(0.0264f, -0.2268f, -0.3055f, 0),
    float4(-0.1003f, -0.1204f, -0.2215f, 0), float4(-0.1125f, 0.1435f, 0.4578f, 0), float4(0.1807f, -0.0244f, 0.0573f, 0), float4(-0.0173f, 0.1901f, -0.0661f, 0),
    float4(0.1722f, -0.0708f, 0.2858f, 0), float4(0.1557f, -0.1323f, -0.6847f, 0), float4(0.1377f, -0.1909f, 0.3506f, 0), float4(-0.2265f, 0.1870f, -0.0745f, 0),
    float4(-0.0583f, -0.0354f, 0.0734f, 0), float4(-0.3126f, -0.0621f, 0.2910f, 0), float4(0.0060f, -0.0115f, 0.5108f, 0), float4(-0.0938f, 0.0874f, 0.2185f, 0),
    float4(0.0683f, -0.1136f, 0.0811f, 0), float4(-0.0657f, -0.1250f, 0.0160f, 0), float4(-0.1506f, 0.0166f, -0.0833f, 0), float4(0.2299f, 0.1196f, -0.1257f, 0),
    float4(0.1128f, 0.0947f, 0.0811f, 0), float4(-0.0550f, -0.2814f, -0.4204f, 0), float4(0.1878f, -0.1307f, 0.2476f, 0), float4(0.0492f, 0.0331f, 0.0053f, 0),
    float4(-0.1049f, 0.0754f, 0.0704f, 0), float4(-0.0179f, -0.2511f, -0.5685f, 0), float4(0.0209f, -0.0317f, -0.0104f, 0), float4(-0.1161f, 0.1662f, -0.1836f, 0),
    float4(-0.2243f, 0.2140f, 0.6126f, 0), float4(-0.0712f, -0.0362f, -0.2636f, 0), float4(-0.1168f, -0.1683f, -0.0230f, 0), float4(-0.0304f, 0.0512f, 0.0787f, 0),
    float4(0.2882f, -0.2166f, 0.1956f, 0), float4(-0.1423f, -0.1441f, 0.1177f, 0), float4(-0.1362f, -0.0676f, 0.1339f, 0), float4(0.0555f, 0.0481f, 0.2314f, 0),
    float4(0.1900f, 0.0589f, -0.0472f, 0), float4(0.1450f, -0.0885f, -0.0083f, 0), float4(-0.3578f, -0.1569f, 0.4160f, 0), float4(-0.0754f, 0.1374f, -0.1214f, 0),
    float4(0.0614f, -0.1509f, -0.2710f, 0), float4(-0.3416f, -0.2051f, 0.2301f, 0), float4(0.0441f, 0.0515f, 0.2869f, 0), float4(-0.0724f, 0.1425f, -0.1936f, 0),
    float4(-0.1850f, 0.1717f, -0.1912f, 0), float4(-0.0196f, -0.0636f, -0.3303f, 0), float4(0.0483f, 0.1233f, -0.0011f, 0), float4(0.0717f, -0.0693f, -0.0987f, 0),
    float4(-0.0186f, -0.1939f, -0.1060f, 0), float4(-0.3491f, -0.2054f, 0.7428f, 0), float4(-0.1012f, 0.0934f, -0.1437f, 0), float4(0.0238f, -0.2342f, -0.3754f, 0),
    float4(-0.1006f, 0.0775f, 0.0554f, 0), float4(-0.1939f, 0.1680f, 0.2175f, 0), float4(0.0245f, 0.0967f, -0.4132f, 0), float4(0.0161f, 0.1607f, -0.0753f, 0),
    float4(-0.3145f, 0.0386f, 0.0256f, 0), float4(-0.3115f, -0.1957f, -0.1022f, 0), float4(-0.0506f, -0.2846f, -0.6136f, 0), float4(-0.1206f, -0.3047f, -0.1527f, 0),
    float4(-0.1770f, -0.1518f, 0.2580f, 0), float4(0.0617f, -0.1138f, 0.1918f, 0), float4(0.3198f, -0.1142f, -0.0433f, 0), float4(0.1829f, 0.0247f, -0.7800f, 0),
    float4(0.0389f, 0.1135f, 0.7151f, 0), float4(-0.1713f, -0.2891f, 0.0613f, 0), float4(-0.2277f, -0.0494f, 0.1265f, 0), float4(0.1112f, -0.1377f, 0.0545f, 0),
    float4(0.0184f, -0.1583f, -0.2421f, 0), float4(0.1724f, 0.0229f, -0.1256f, 0), float4(-0.1279f, -0.2654f, -0.0282f, 0), float4(0.0175f, -0.2562f, 0.0789f, 0),
    float4(-0.0159f, -0.2238f, -0.1483f, 0), float4(-0.0899f, 0.1005f, 0.0890f, 0), float4(0.0694f, -0.0675f, 0.6524f, 0), float4(-0.1994f, 0.0865f, -0.0378f, 0),
    float4(0.3125f, 0.0752f, -0.3787f, 0), float4(0.0237f, -0.0585f, -0.1768f, 0), float4(-0.3828f, 0.1708f, -0.1759f, 0), float4(-0.1055f, -0.1526f, -0.0286f, 0),
    float4(-0.3401f, 0.1498f, -0.2110f, 0), float4(-0.3699f, -0.1859f, 0.5868f, 0), float4(0.3064f, -0.0415f, 0.2421f, 0), float4(0.0374f, 0.1189f, 0.0088f, 0),
    float4(-0.0432f, -0.2221f, -0.0365f, 0), float4(0.0054f, -0.1075f, -0.0330f, 0), float4(-0.1467f, -0.1268f, 0.0073f, 0), float4(0.0194f, -0.1953f, 0.1026f, 0),
    float4(-0.0411f, -0.0241f, -0.2629f, 0), float4(-0.0397f, -0.2486f, 0.4739f, 0), float4(-0.1599f, -0.0674f, 0.1497f, 0), float4(0.0332f, 0.0585f, -0.0145f, 0),
    float4(-0.2279f, -0.1100f, -0.2369f, 0), float4(0.2896f, -0.1901f, 0.3984f, 0), float4(-0.2674f, 0.0234f, 0.2396f, 0), float4(0.0201f, -0.1772f, 0.0687f, 0),
    float4(0.2032f, -0.1243f, -0.2145f, 0), float4(0.1913f, -0.0769f, 0.1747f, 0), float4(0.2961f, -0.0244f, -0.0150f, 0), float4(0.2028f, 0.1911f, 0.2004f, 0),
    float4(-0.3595f, -0.1363f, -0.0237f, 0), float4(0.0246f, -0.2747f, -0.1586f, 0), float4(-0.0553f, -0.0222f, 0.0141f, 0), float4(-0.0296f, 0.0972f, -0.2032f, 0),
    float4(0.0929f, 0.1556f, -0.2503f, 0), float4(-0.1835f, 0.1746f, -0.2609f, 0), float4(-0.2923f, -0.2826f, -0.1834f, 0), float4(-0.1679f, 0.0073f, -0.4709f, 0),
    float4(-0.3841f, -0.2419f, -0.1773f, 0), float4(0.0016f, -0.2767f, -0.1386f, 0), float4(0.1836f, -0.1700f, -0.0381f, 0), float4(0.0047f, 0.0340f, -0.0277f, 0),
    float4(-0.3096f, -0.0139f, 0.2278f, 0), float4(0.0733f, 0.0687f, 0.1348f, 0), float4(0.2920f, 0.1754f, -0.1820f, 0), float4(0.1341f, 0.0721f, -0.2781f, 0),
    float4(-0.1408f, 0.1184f, -0.0695f, 0), float4(0.0708f, -0.2113f, -0.0801f, 0), float4(0.2117f, -0.0097f, 0.0752f, 0), float4(-0.2299f, 0.1746f, -0.1336f, 0),
    float4(-0.3393f, 0.1097f, 0.4536f, 0), float4(0.1519f, -0.1118f, 0.3756f, 0), float4(0.1075f, 0.0503f, 0.2840f, 0), float4(-0.2037f, -0.1346f, -0.4028f, 0),
    float4(0.0428f, -0.0758f, 0.1151f, 0), float4(-0.1878f, -0.0578f, 0.0661f, 0), float4(-0.0938f, 0.1390f, -0.5949f, 0), float4(-0.1220f, -0.2155f, 0.0407f, 0),
    float4(-0.1691f, 0.1080f, 0.2067f, 0), float4(0.1378f, -0.0000f, 0.2022f, 0), float4(-0.2758f, 0.0713f, -0.5736f, 0), float4(-0.1363f, -0.0705f, 0.1955f, 0),
    float4(-0.1171f, -0.0446f, 0.0727f, 0), float4(-0.3520f, 0.0128f, -0.5917f, 0), float4(0.2428f, -0.0928f, -0.4745f, 0), float4(-0.0129f, -0.2497f, -0.0455f, 0),
    float4(0.3192f, 0.1893f, -0.0220f, 0), float4(0.0619f, -0.0350f, -0.1851f, 0), float4(-0.1215f, -0.1431f, -0.0238f, 0), float4(-0.0848f, -0.1839f, -0.1309f, 0),
    float4(0.0296f, 0.1531f, 0.0443f, 0), float4(-0.0292f, 0.1675f, 0.3286f, 0), float4(-0.0676f, -0.0072f, 0.0554f, 0), float4(0.0001f, -0.0385f, 0.1558f, 0),
    float4(-0.1082f, -0.2297f, 0.1306f, 0), float4(-0.2133f, -0.2166f, -0.3645f, 0), float4(0.1201f, -0.1660f, 0.0604f, 0), float4(0.0719f, -0.1062f, -0.2950f, 0),
    float4(0.0067f, 0.1558f, 0.1840f, 0), float4(0.1038f, -0.2159f, 0.2193f, 0), float4(-0.0744f, -0.0604f, -0.2791f, 0), float4(0.0407f, 0.1154f, 0.2177f, 0),
    float4(0.0904f, 0.1067f, -0.1917f, 0), float4(0.1916f, -0.2124f, 0.0530f, 0), float4(-0.0949f, -0.1502f, 0.3312f, 0), float4(0.0337f, 0.0724f, -0.2083f, 0),
    float4(-0.1679f, 0.1375f, -0.0026f, 0), float4(-0.0294f, -0.2120f, -0.2619f, 0), float4(0.1830f, -0.1327f, 0.0927f, 0), float4(-0.1378f, -0.0287f, 0.6500f, 0),
    float4(-0.0089f, -0.0778f, 0.4649f, 0), float4(-0.2422f, 0.2050f, -0.0539f, 0), float4(0.2662f, -0.0868f, 0.1311f, 0), float4(0.3082f, -0.0022f, 0.0396f, 0),
    float4(0.0216f, -0.0476f, 0.2879f, 0), float4(-0.1285f, -0.1660f, -0.0748f, 0), float4(0.0538f, 0.0134f, 0.0038f, 0), float4(-0.0768f, -0.2804f, 0.1046f, 0),
    float4(0.0131f, -0.2757f, 0.1331f, 0), float4(-0.0114f, -0.2723f, 0.6925f, 0), float4(-0.1401f, 0.1219f, 0.2984f, 0), float4(-0.0502f, -0.1711f, -0.0191f, 0),
    float4(0.2805f, 0.1013f, 0.4335f, 0), float4(0.0633f, 0.0813f, -0.0646f, 0), float4(0.0182f, -0.1092f, -0.7900f, 0), float4(-0.1049f, 0.1294f, -0.1247f, 0),
    float4(-0.2957f, -0.2062f, -0.0814f, 0), float4(0.1065f, 0.1306f, 0.4105f, 0), float4(0.0785f, -0.1158f, -0.3787f, 0), float4(0.0519f, 0.0080f, -0.0272f, 0),
    float4(0.1215f, -0.1254f, -0.1105f, 0), float4(-0.3162f, 0.1025f, 0.3317f, 0), float4(0.0469f, -0.0908f, -0.1052f, 0), float4(-0.1544f, -0.1929f, 0.0996f, 0),
    float4(0.2060f, 0.2105f, 0.2858f, 0), float4(-0.3043f, -0.2504f, -0.1177f, 0), float4(-0.2144f, -0.1588f, 0.0512f, 0), float4(-0.3928f, 0.0293f, -0.0137f, 0),
    float4(-0.2416f, -0.2789f, -0.7151f, 0), float4(-0.1901f, -0.0224f, -0.0532f, 0), float4(-0.2287f, -0.0432f, -0.1398f, 0), float4(0.2617f, 0.0489f, -0.3055f, 0),
    float4(-0.3331f, -0.2946f, 0.1430f, 0), float4(0.1497f, -0.1658f, 0.2358f, 0), float4(0.3034f, 0.0122f, 0.6694f, 0), float4(-0.0071f, 0.1429f, 0.0827f, 0),
    float4(-0.1535f, -0.1713f, -0.0459f, 0), float4(-0.0748f, -0.1297f, -0.6337f, 0), float4(0.0375f, -0.1248f, -0.3785f, 0), float4(-0.1029f, 0.1488f, -0.5971f, 0),
    float4(0.2055f, -0.1496f, -0.0643f, 0), float4(0.0378f, -0.1211f, 0.0901f, 0), float4(-0.0455f, 0.1462f, 0.0673f, 0), float4(-0.2315f, 0.0495f, 0.2081f, 0),
    float4(-0.1433f, -0.0722f, -0.0505f, 0), float4(-0.1362f, -0.1439f, -0.7631f, 0), float4(0.2493f, 0.1510f, -0.2732f, 0), float4(-0.2212f, 0.1608f, 0.0690f, 0),
    float4(-0.0275f, 0.0222f, 0.0123f, 0), float4(-0.0135f, 0.1415f, 0.4650f, 0), float4(0.0643f, 0.0305f, -0.0982f, 0), float4(0.2226f, -0.1926f, -0.6085f, 0),
    float4(-0.2695f, -0.1219f, -0.0947f, 0), float4(0.0550f, 0.0049f, -0.0810f, 0), float4(-0.2679f, 0.0592f, -0.1991f, 0), float4(0.2827f, 0.0096f, 0.0641f, 0),
    float4(-0.2718f, -0.1386f, 0.2965f, 0), float4(-0.3607f, 0.0999f, 0.4734f, 0), float4(0.0359f, -0.0950f, 0.0121f, 0), float4(0.0930f, -0.1487f, -0.1603f, 0),
    float4(-0.2867f, -0.2145f, 0.6708f, 0), float4(-0.0563f, 0.1564f, 0.2927f, 0), float4(-0.0806f, -0.0947f, -0.0475f, 0), float4(0.1750f, -0.2856f, -0.0784f, 0),
    float4(-0.2634f, -0.2837f, -0.6029f, 0), float4(-0.0593f, 0.1675f, 0.1343f, 0), float4(0.0555f, 0.2113f, -0.5665f, 0), float4(0.0419f, 0.1424f, -0.1343f, 0),
    float4(-0.0278f, 0.1323f, -0.2947f, 0), float4(-0.1168f, 0.0193f, 0.4123f, 0), float4(0.0621f, -0.3049f, 0.0348f, 0), float4(0.1223f, 0.0155f, 0.0853f, 0),
    float4(-0.2821f, -0.2047f, -0.1602f, 0), float4(-0.2249f, -0.1316f, 0.3960f, 0), float4(-0.1691f, 0.0541f, -0.0653f, 0), float4(0.0716f, 0.1831f, 0.0564f, 0),
    float4(0.1320f, 0.1078f, 0.0983f, 0),
};
constant float4 STAR_XYZ[N_STARS] = {   // CIE XYZ flux, erg/s/cm2 x CMF, before extinction
    float4(3.4092e-08f, 3.3730e-08f, 6.9873e-08f, 0), float4(1.0679e-08f, 1.0647e-08f, 2.1032e-08f, 0), float4(1.0659e-08f, 1.0564e-08f, 2.1656e-08f, 0), float4(7.9953e-09f, 7.9373e-09f, 1.6112e-08f, 0),
    float4(7.7655e-09f, 7.7187e-09f, 1.5548e-08f, 0), float4(2.4919e-09f, 2.4845e-09f, 4.9078e-09f, 0), float4(5.7214e-10f, 5.8756e-10f, 8.7840e-10f, 0), float4(4.8311e-10f, 4.8212e-10f, 9.4668e-10f, 0),
    float4(3.3140e-10f, 3.3828e-10f, 5.4916e-10f, 0), float4(3.0839e-10f, 3.1699e-10f, 4.6651e-10f, 0), float4(2.1481e-10f, 2.2138e-10f, 3.0851e-10f, 0), float4(9.2832e-11f, 9.4714e-11f, 8.1640e-11f, 0),
    float4(4.7077e-12f, 4.4059e-12f, 1.8170e-12f, 0), float4(4.5804e-12f, 4.2839e-12f, 1.7587e-12f, 0), float4(4.8031e-12f, 4.4975e-12f, 1.8610e-12f, 0), float4(2.1670e-11f, 2.1104e-11f, 1.1591e-11f, 0),
    float4(1.5433e-11f, 1.4912e-11f, 7.7125e-12f, 0), float4(2.1211e-12f, 1.9522e-12f, 7.2000e-13f, 0), float4(4.3943e-12f, 4.1057e-12f, 1.6741e-12f, 0), float4(1.9461e-12f, 1.7857e-12f, 6.4568e-13f, 0),
    float4(3.2122e-11f, 3.1568e-11f, 1.8643e-11f, 0), float4(6.8783e-11f, 6.8814e-11f, 4.7558e-11f, 0), float4(6.9712e-12f, 6.5922e-12f, 2.9188e-12f, 0), float4(3.1070e-11f, 3.0513e-11f, 1.7914e-11f, 0),
    float4(6.7790e-11f, 6.7796e-11f, 4.6695e-11f, 0), float4(2.0504e-12f, 1.8860e-12f, 6.9288e-13f, 0), float4(1.9202e-11f, 1.8646e-11f, 1.0014e-11f, 0), float4(8.6338e-12f, 8.2152e-12f, 3.7995e-12f, 0),
    float4(1.9527e-12f, 1.7921e-12f, 6.4886e-13f, 0), float4(9.5799e-11f, 9.6436e-11f, 7.0887e-11f, 0), float4(2.9097e-12f, 2.6939e-12f, 1.0335e-12f, 0), float4(5.4039e-12f, 5.0751e-12f, 2.1431e-12f, 0),
    float4(2.6531e-10f, 2.7235e-10f, 2.5862e-10f, 0), float4(2.8029e-11f, 2.7466e-11f, 1.5841e-11f, 0), float4(1.5935e-11f, 1.5408e-11f, 8.0115e-12f, 0), float4(2.1639e-12f, 1.9922e-12f, 7.3647e-13f, 0),
    float4(2.4018e-11f, 2.3450e-11f, 1.3137e-11f, 0), float4(3.6510e-12f, 3.3967e-12f, 1.3457e-12f, 0), float4(3.5782e-12f, 3.3274e-12f, 1.3143e-12f, 0), float4(4.0382e-11f, 3.9890e-11f, 2.4587e-11f, 0),
    float4(2.2453e-12f, 2.0685e-12f, 7.6801e-13f, 0), float4(3.4250e-12f, 3.1819e-12f, 1.2488e-12f, 0), float4(6.2170e-11f, 6.2045e-11f, 4.1891e-11f, 0), float4(8.6621e-12f, 8.2430e-12f, 3.8150e-12f, 0),
    float4(1.5550e-10f, 1.5772e-10f, 1.2610e-10f, 0), float4(1.9737e-11f, 1.9179e-11f, 1.0352e-11f, 0), float4(9.5503e-12f, 9.1152e-12f, 4.3086e-12f, 0), float4(2.1533e-12f, 1.9823e-12f, 7.3239e-13f, 0),
    float4(1.4847e-11f, 1.4334e-11f, 7.3667e-12f, 0), float4(2.1523e-10f, 2.1943e-10f, 1.8726e-10f, 0), float4(2.6433e-11f, 2.5871e-11f, 1.4774e-11f, 0), float4(2.3367e-12f, 2.1543e-12f, 8.0369e-13f, 0),
    float4(1.8281e-11f, 1.7731e-11f, 9.4397e-12f, 0), float4(3.0281e-12f, 2.8059e-12f, 1.0823e-12f, 0), float4(2.5592e-11f, 2.5027e-11f, 1.4199e-11f, 0), float4(1.8811e-12f, 1.7226e-12f, 6.1470e-13f, 0),
    float4(4.5098e-11f, 4.4662e-11f, 2.8141e-11f, 0), float4(2.4570e-11f, 2.4002e-11f, 1.3507e-11f, 0), float4(2.7407e-12f, 2.5345e-12f, 9.6468e-13f, 0), float4(6.6213e-11f, 6.6181e-11f, 4.5334e-11f, 0),
    float4(3.8102e-11f, 3.7588e-11f, 2.2909e-11f, 0), float4(2.9332e-12f, 2.7162e-12f, 1.0432e-12f, 0), float4(1.6949e-10f, 1.7216e-10f, 1.3994e-10f, 0), float4(1.4055e-11f, 1.3554e-11f, 6.9048e-12f, 0),
    float4(1.4027e-12f, 1.2627e-12f, 4.0360e-13f, 0), float4(4.5278e-12f, 4.2336e-12f, 1.7347e-12f, 0), float4(3.3271e-12f, 3.0890e-12f, 1.2073e-12f, 0), float4(2.7837e-11f, 2.7273e-11f, 1.5711e-11f, 0),
    float4(1.9334e-11f, 1.8778e-11f, 1.0097e-11f, 0), float4(1.8458e-12f, 1.6884e-12f, 5.9812e-13f, 0), float4(1.8214e-12f, 1.6647e-12f, 5.8671e-13f, 0), float4(8.5380e-12f, 8.1214e-12f, 3.7473e-12f, 0),
    float4(1.2378e-10f, 1.2510e-10f, 9.5949e-11f, 0), float4(1.3010e-11f, 1.2525e-11f, 6.3048e-12f, 0), float4(5.7806e-11f, 5.7588e-11f, 3.8252e-11f, 0), float4(1.5574e-11f, 1.5052e-11f, 7.7965e-12f, 0),
    float4(1.9113e-11f, 1.8558e-11f, 9.9588e-12f, 0), float4(1.0677e-11f, 1.0226e-11f, 4.9559e-12f, 0), float4(2.7036e-11f, 2.6473e-11f, 1.5175e-11f, 0), float4(8.8009e-11f, 8.8482e-11f, 6.4192e-11f, 0),
    float4(9.2160e-12f, 8.7865e-12f, 4.1211e-12f, 0), float4(1.4820e-12f, 1.3383e-12f, 4.3645e-13f, 0), float4(3.8067e-11f, 3.7553e-11f, 2.2884e-11f, 0), float4(8.7359e-12f, 8.3154e-12f, 3.8555e-12f, 0),
    float4(9.1741e-12f, 8.7454e-12f, 4.0977e-12f, 0), float4(8.3585e-11f, 8.3970e-11f, 6.0448e-11f, 0), float4(2.6093e-12f, 2.4106e-12f, 9.1171e-13f, 0), float4(3.8155e-12f, 3.5532e-12f, 1.4171e-12f, 0),
    float4(1.3295e-11f, 1.2805e-11f, 6.4672e-12f, 0), float4(4.8775e-11f, 4.8393e-11f, 3.0989e-11f, 0), float4(2.5768e-12f, 2.3801e-12f, 8.9874e-13f, 0), float4(1.7785e-12f, 1.6233e-12f, 5.6692e-13f, 0),
    float4(1.3874e-12f, 1.2481e-12f, 3.9734e-13f, 0), float4(6.8835e-12f, 6.5069e-12f, 2.8739e-12f, 0), float4(2.2098e-11f, 2.1531e-11f, 1.1869e-11f, 0), float4(5.3924e-12f, 5.0641e-12f, 2.1376e-12f, 0),
    float4(8.2764e-11f, 8.3133e-11f, 5.9759e-11f, 0), float4(1.5601e-11f, 1.5078e-11f, 7.8123e-12f, 0), float4(3.1586e-11f, 3.1030e-11f, 1.8270e-11f, 0), float4(1.4747e-11f, 1.4235e-11f, 7.3079e-12f, 0),
    float4(2.8438e-12f, 2.6317e-12f, 1.0066e-12f, 0), float4(1.6437e-12f, 1.4933e-12f, 5.0616e-13f, 0), float4(3.2086e-11f, 3.1532e-11f, 1.8618e-11f, 0), float4(1.4930e-12f, 1.3488e-12f, 4.4110e-13f, 0),
    float4(1.2957e-11f, 1.2473e-11f, 6.2745e-12f, 0), float4(1.0764e-11f, 1.0312e-11f, 5.0070e-12f, 0), float4(8.0803e-11f, 8.1136e-11f, 5.8117e-11f, 0), float4(1.9332e-12f, 1.7731e-12f, 6.3947e-13f, 0),
    float4(1.4145e-12f, 1.2740e-12f, 4.0844e-13f, 0), float4(2.0280e-11f, 1.9719e-11f, 1.0696e-11f, 0), float4(3.2784e-11f, 3.2234e-11f, 1.9106e-11f, 0), float4(4.0183e-12f, 3.7466e-12f, 1.5062e-12f, 0),
    float4(2.6138e-12f, 2.4149e-12f, 9.1352e-13f, 0), float4(1.4027e-11f, 1.3525e-11f, 6.8883e-12f, 0), float4(1.4328e-11f, 1.3823e-11f, 7.0635e-12f, 0), float4(4.9039e-11f, 4.8662e-11f, 3.1196e-11f, 0),
    float4(2.5044e-11f, 2.4478e-11f, 1.3827e-11f, 0), float4(4.5346e-11f, 4.4913e-11f, 2.8331e-11f, 0), float4(2.1647e-11f, 2.1081e-11f, 1.1575e-11f, 0), float4(1.2175e-11f, 1.1705e-11f, 5.8332e-12f, 0),
    float4(6.7691e-12f, 6.3958e-12f, 2.8157e-12f, 0), float4(3.7351e-12f, 3.4767e-12f, 1.3821e-12f, 0), float4(2.7371e-11f, 2.6807e-11f, 1.5399e-11f, 0), float4(1.8393e-11f, 1.7843e-11f, 9.5095e-12f, 0),
    float4(2.4480e-11f, 2.3913e-11f, 1.3447e-11f, 0), float4(2.0094e-10f, 2.0464e-10f, 1.7215e-10f, 0), float4(5.0793e-11f, 5.0444e-11f, 3.2579e-11f, 0), float4(5.1756e-12f, 4.8553e-12f, 2.0348e-12f, 0),
    float4(5.4096e-11f, 5.3805e-11f, 3.5223e-11f, 0), float4(2.7171e-12f, 2.5122e-12f, 9.5512e-13f, 0), float4(2.5122e-12f, 2.3193e-12f, 8.7299e-13f, 0), float4(1.5048e-12f, 1.3601e-12f, 4.4607e-13f, 0),
    float4(3.2296e-11f, 3.1743e-11f, 1.8764e-11f, 0), float4(1.2965e-11f, 1.2481e-11f, 6.2793e-12f, 0), float4(6.1789e-12f, 5.8236e-12f, 2.5198e-12f, 0), float4(7.5953e-12f, 7.1999e-12f, 3.2427e-12f, 0),
    float4(2.6728e-11f, 2.6166e-11f, 1.4971e-11f, 0), float4(2.1684e-12f, 1.9965e-12f, 7.3822e-13f, 0), float4(6.0081e-11f, 5.9910e-11f, 4.0138e-11f, 0), float4(1.3541e-10f, 1.3705e-10f, 1.0680e-10f, 0),
    float4(2.3314e-12f, 2.1493e-12f, 8.0161e-13f, 0), float4(2.8064e-12f, 2.5965e-12f, 9.9134e-13f, 0), float4(2.9405e-11f, 2.8843e-11f, 1.6771e-11f, 0), float4(1.3095e-11f, 1.2609e-11f, 6.3532e-12f, 0),
    float4(1.1115e-11f, 1.0660e-11f, 5.2144e-12f, 0), float4(2.4189e-12f, 2.2316e-12f, 8.3603e-13f, 0), float4(1.5871e-11f, 1.5345e-11f, 7.9731e-12f, 0), float4(3.9374e-11f, 3.8871e-11f, 2.3842e-11f, 0),
    float4(3.6584e-11f, 3.6058e-11f, 2.1808e-11f, 0), float4(2.0504e-10f, 2.0888e-10f, 1.7646e-10f, 0), float4(7.3788e-11f, 7.3949e-11f, 5.1966e-11f, 0), float4(6.9592e-12f, 6.5805e-12f, 2.9127e-12f, 0),
    float4(6.8845e-12f, 6.5079e-12f, 2.8745e-12f, 0), float4(1.4427e-11f, 1.3920e-11f, 7.1209e-12f, 0), float4(1.4486e-12f, 1.3064e-12f, 4.2249e-13f, 0), float4(1.5361e-11f, 1.4841e-11f, 7.6697e-12f, 0),
    float4(1.7209e-11f, 1.6669e-11f, 8.7808e-12f, 0), float4(1.0662e-11f, 1.0211e-11f, 4.9473e-12f, 0), float4(4.0618e-12f, 3.7880e-12f, 1.5254e-12f, 0), float4(1.4294e-12f, 1.2881e-12f, 4.1455e-13f, 0),
    float4(4.7438e-12f, 4.4405e-12f, 1.8336e-12f, 0), float4(2.0677e-12f, 1.9022e-12f, 6.9951e-13f, 0), float4(4.4272e-11f, 4.3825e-11f, 2.7510e-11f, 0), float4(2.1388e-11f, 2.0823e-11f, 1.1408e-11f, 0),
    float4(1.6372e-11f, 1.5840e-11f, 8.2738e-12f, 0), float4(1.8215e-11f, 1.7666e-11f, 9.3991e-12f, 0), float4(7.0749e-12f, 6.6931e-12f, 2.9721e-12f, 0), float4(1.4662e-12f, 1.3233e-12f, 4.2986e-13f, 0),
    float4(4.5371e-12f, 4.2425e-12f, 1.7389e-12f, 0), float4(3.7701e-12f, 3.5100e-12f, 1.3973e-12f, 0), float4(4.0985e-11f, 4.0500e-11f, 2.5035e-11f, 0), float4(2.8141e-11f, 2.7578e-11f, 1.5916e-11f, 0),
    float4(4.1868e-11f, 4.1392e-11f, 2.5695e-11f, 0), float4(2.0516e-12f, 1.8871e-12f, 6.9333e-13f, 0), float4(1.1715e-11f, 1.1254e-11f, 5.5731e-12f, 0), float4(8.1517e-11f, 8.1863e-11f, 5.8714e-11f, 0),
    float4(1.7603e-12f, 1.6057e-12f, 5.5858e-13f, 0), float4(1.9600e-11f, 1.9042e-11f, 1.0265e-11f, 0), float4(2.2602e-12f, 2.0826e-12f, 7.7383e-13f, 0), float4(1.2399e-11f, 1.1925e-11f, 5.9590e-12f, 0),
    float4(4.8186e-11f, 4.7795e-11f, 3.0528e-11f, 0), float4(1.0585e-10f, 1.0672e-10f, 7.9710e-11f, 0), float4(1.3638e-12f, 1.2258e-12f, 3.8780e-13f, 0), float4(1.8332e-12f, 1.6762e-12f, 5.9222e-13f, 0),
    float4(1.8973e-12f, 1.7383e-12f, 6.2239e-13f, 0), float4(1.3320e-11f, 1.2830e-11f, 6.4813e-12f, 0), float4(3.0575e-12f, 2.8337e-12f, 1.0945e-12f, 0), float4(5.0195e-11f, 4.9836e-11f, 3.2106e-11f, 0),
    float4(2.0079e-12f, 1.8458e-12f, 6.7561e-13f, 0), float4(1.8113e-12f, 1.6550e-12f, 5.8204e-13f, 0), float4(1.6035e-12f, 1.4547e-12f, 4.8851e-13f, 0), float4(2.2962e-12f, 2.1163e-12f, 7.8786e-13f, 0),
    float4(1.1797e-11f, 1.1335e-11f, 5.6225e-12f, 0), float4(4.2167e-12f, 3.9360e-12f, 1.5943e-12f, 0), float4(9.7787e-12f, 9.3399e-12f, 4.4379e-12f, 0), float4(2.2621e-11f, 2.2053e-11f, 1.2211e-11f, 0),
    float4(3.6726e-12f, 3.4172e-12f, 1.3550e-12f, 0), float4(1.4057e-11f, 1.3555e-11f, 6.9058e-12f, 0), float4(7.1754e-12f, 6.7908e-12f, 3.0239e-12f, 0), float4(6.1613e-11f, 6.1476e-11f, 4.1422e-11f, 0),
    float4(2.4966e-11f, 2.4399e-11f, 1.3774e-11f, 0), float4(9.9763e-12f, 9.5346e-12f, 4.5507e-12f, 0), float4(1.9679e-12f, 1.8069e-12f, 6.5616e-13f, 0), float4(1.5756e-10f, 1.5985e-10f, 1.2812e-10f, 0),
    float4(1.8310e-12f, 1.6740e-12f, 5.9120e-13f, 0), float4(1.1573e-10f, 1.1684e-10f, 8.8583e-11f, 0), float4(1.1100e-11f, 1.0644e-11f, 5.2052e-12f, 0), float4(1.2223e-10f, 1.2351e-10f, 9.4525e-11f, 0),
    float4(1.5713e-12f, 1.4238e-12f, 4.7453e-13f, 0), float4(2.4636e-11f, 2.4068e-11f, 1.3551e-11f, 0), float4(3.8848e-12f, 3.6192e-12f, 1.4474e-12f, 0), float4(7.2080e-12f, 6.8226e-12f, 3.0408e-12f, 0),
    float4(2.2691e-12f, 2.0909e-12f, 7.7728e-13f, 0), float4(2.1248e-12f, 1.9556e-12f, 7.2140e-13f, 0), float4(2.7716e-10f, 2.8488e-10f, 2.7749e-10f, 0), float4(4.6121e-12f, 4.3143e-12f, 1.7731e-12f, 0),
    float4(5.1896e-12f, 4.8688e-12f, 2.0415e-12f, 0), float4(8.0836e-12f, 7.6767e-12f, 3.5018e-12f, 0), float4(7.4778e-12f, 7.0854e-12f, 3.1811e-12f, 0), float4(3.3012e-12f, 3.0645e-12f, 1.1964e-12f, 0),
    float4(1.5124e-12f, 1.3674e-12f, 4.4929e-13f, 0), float4(3.2085e-12f, 2.9766e-12f, 1.1574e-12f, 0), float4(9.3326e-12f, 8.9011e-12f, 4.1862e-12f, 0), float4(3.4333e-10f, 3.5442e-10f, 3.8906e-10f, 0),
    float4(1.0669e-11f, 1.0218e-11f, 4.9513e-12f, 0), float4(5.0440e-12f, 4.7288e-12f, 1.9730e-12f, 0), float4(2.3141e-11f, 2.2572e-11f, 1.2554e-11f, 0), float4(1.6208e-10f, 1.6451e-10f, 1.3257e-10f, 0),
    float4(2.1835e-12f, 2.0106e-12f, 7.4405e-13f, 0), float4(2.1656e-12f, 1.9939e-12f, 7.3716e-13f, 0), float4(4.4352e-12f, 4.1449e-12f, 1.6926e-12f, 0), float4(4.0740e-12f, 3.7997e-12f, 1.5308e-12f, 0),
    float4(2.1627e-11f, 2.1061e-11f, 1.1563e-11f, 0), float4(1.7275e-11f, 1.6735e-11f, 8.8215e-12f, 0), float4(1.1193e-11f, 1.0737e-11f, 5.2605e-12f, 0), float4(1.9343e-11f, 1.8787e-11f, 1.0103e-11f, 0),
    float4(8.1580e-12f, 7.7494e-12f, 3.5417e-12f, 0), float4(2.7087e-12f, 2.5043e-12f, 9.5173e-13f, 0), float4(8.4271e-12f, 8.0128e-12f, 3.6870e-12f, 0), float4(3.7950e-11f, 3.7434e-11f, 2.2798e-11f, 0),
    float4(7.5976e-12f, 7.2022e-12f, 3.2440e-12f, 0), float4(1.7495e-12f, 1.5953e-12f, 5.5365e-13f, 0), float4(9.8791e-12f, 9.4388e-12f, 4.4951e-12f, 0), float4(6.6411e-12f, 6.2716e-12f, 2.7509e-12f, 0),
    float4(1.3026e-11f, 1.2541e-11f, 6.3136e-12f, 0), float4(9.3934e-12f, 8.9609e-12f, 4.2203e-12f, 0), float4(3.2157e-12f, 2.9835e-12f, 1.1605e-12f, 0), float4(1.6757e-12f, 1.5241e-12f, 5.2037e-13f, 0),
    float4(6.9344e-11f, 6.9389e-11f, 4.8047e-11f, 0), float4(1.6440e-11f, 1.5908e-11f, 8.3150e-12f, 0), float4(1.9865e-12f, 1.8250e-12f, 6.6520e-13f, 0), float4(1.6347e-11f, 1.5816e-11f, 8.2588e-12f, 0),
    float4(1.3232e-10f, 1.3387e-10f, 1.0389e-10f, 0), float4(1.6876e-11f, 1.6339e-11f, 8.5785e-12f, 0), float4(3.0145e-11f, 2.9585e-11f, 1.7277e-11f, 0), float4(6.8594e-12f, 6.4835e-12f, 2.8616e-12f, 0),
    float4(9.5742e-11f, 9.6379e-11f, 7.0838e-11f, 0), float4(2.8712e-12f, 2.6576e-12f, 1.0178e-12f, 0), float4(2.8230e-12f, 2.6122e-12f, 9.9811e-13f, 0), float4(2.8442e-10f, 2.9254e-10f, 2.8922e-10f, 0),
    float4(8.6362e-11f, 8.6802e-11f, 6.2794e-11f, 0), float4(1.7084e-10f, 1.7355e-10f, 1.4129e-10f, 0), float4(8.7110e-12f, 8.2909e-12f, 3.8418e-12f, 0), float4(2.1908e-12f, 2.0174e-12f, 7.4687e-13f, 0),
    float4(3.1711e-11f, 3.1156e-11f, 1.8357e-11f, 0), float4(8.4288e-12f, 8.0144e-12f, 3.6879e-12f, 0), float4(7.0972e-12f, 6.7147e-12f, 2.9835e-12f, 0), float4(1.7559e-12f, 1.6014e-12f, 5.5656e-13f, 0),
    float4(1.8638e-12f, 1.7058e-12f, 6.0654e-13f, 0), float4(1.6696e-12f, 1.5182e-12f, 5.1766e-13f, 0), float4(9.2031e-12f, 8.7739e-12f, 4.1139e-12f, 0), float4(1.3621e-12f, 1.2241e-12f, 3.8710e-13f, 0),
    float4(2.3492e-11f, 2.2924e-11f, 1.2787e-11f, 0), float4(4.9889e-12f, 4.6758e-12f, 1.9473e-12f, 0), float4(6.3043e-12f, 5.9450e-12f, 2.5820e-12f, 0), float4(3.1162e-12f, 2.8892e-12f, 1.1188e-12f, 0),
    float4(6.5561e-11f, 6.5514e-11f, 4.4774e-11f, 0), float4(3.2220e-12f, 2.9895e-12f, 1.1631e-12f, 0), float4(1.5010e-12f, 1.3564e-12f, 4.4444e-13f, 0), float4(2.3043e-11f, 2.2475e-11f, 1.2490e-11f, 0),
    float4(1.8901e-11f, 1.8348e-11f, 9.8262e-12f, 0), float4(2.5741e-12f, 2.3775e-12f, 8.9763e-13f, 0), float4(3.9832e-12f, 3.7131e-12f, 1.4907e-12f, 0), float4(1.5304e-12f, 1.3846e-12f, 4.5693e-13f, 0),
    float4(5.3109e-11f, 5.2800e-11f, 3.4427e-11f, 0), float4(9.5054e-12f, 9.0710e-12f, 4.2833e-12f, 0), float4(6.3080e-12f, 5.9486e-12f, 2.5838e-12f, 0), float4(1.4885e-10f, 1.5087e-10f, 1.1964e-10f, 0),
    float4(5.9975e-12f, 5.6480e-12f, 2.4303e-12f, 0), float4(3.5656e-12f, 3.3155e-12f, 1.3089e-12f, 0), float4(9.5674e-12f, 9.1321e-12f, 4.3183e-12f, 0), float4(2.3976e-12f, 2.2115e-12f, 8.2761e-13f, 0),
    float4(1.3822e-12f, 1.2432e-12f, 3.9524e-13f, 0), float4(2.0351e-12f, 1.8717e-12f, 6.8706e-13f, 0), float4(4.8526e-11f, 4.8140e-11f, 3.0794e-11f, 0), float4(2.5355e-12f, 2.3412e-12f, 8.8224e-13f, 0),
    float4(1.8161e-11f, 1.7613e-11f, 9.3660e-12f, 0), float4(3.1501e-11f, 3.0945e-11f, 1.8211e-11f, 0), float4(4.6831e-12f, 4.3823e-12f, 1.8057e-12f, 0), float4(4.0020e-11f, 3.9524e-11f, 2.4319e-11f, 0),
    float4(4.9002e-12f, 4.5907e-12f, 1.9060e-12f, 0), float4(1.4741e-12f, 1.3308e-12f, 4.3316e-13f, 0), float4(1.9021e-11f, 1.8467e-11f, 9.9012e-12f, 0), float4(1.5447e-12f, 1.3983e-12f, 4.6308e-13f, 0),
    float4(4.0334e-12f, 3.7609e-12f, 1.5128e-12f, 0), float4(9.0002e-12f, 8.5747e-12f, 4.0011e-12f, 0), float4(6.3446e-11f, 6.3350e-11f, 4.2971e-11f, 0), float4(5.9400e-12f, 5.5924e-12f, 2.4021e-12f, 0),
    float4(3.4165e-12f, 3.1739e-12f, 1.2452e-12f, 0), float4(5.0291e-12f, 4.7144e-12f, 1.9661e-12f, 0), float4(6.2406e-11f, 6.2286e-11f, 4.2090e-11f, 0), float4(1.9238e-11f, 1.8682e-11f, 1.0037e-11f, 0),
    float4(2.1722e-11f, 2.1156e-11f, 1.1624e-11f, 0), float4(3.1646e-11f, 3.1091e-11f, 1.8312e-11f, 0), float4(3.1731e-11f, 3.1176e-11f, 1.8371e-11f, 0), float4(2.4196e-12f, 2.2322e-12f, 8.3628e-13f, 0),
    float4(9.9752e-12f, 9.5335e-12f, 4.5500e-12f, 0), float4(1.5513e-11f, 1.4991e-11f, 7.7603e-12f, 0), float4(2.3638e-11f, 2.3069e-11f, 1.2883e-11f, 0), float4(8.3026e-12f, 7.8909e-12f, 3.6196e-12f, 0),
    float4(4.3842e-12f, 4.0961e-12f, 1.6696e-12f, 0), float4(1.1433e-11f, 1.0974e-11f, 5.4034e-12f, 0), float4(3.4161e-10f, 3.5262e-10f, 3.8604e-10f, 0), float4(1.0418e-11f, 9.9701e-12f, 4.8052e-12f, 0),
    float4(7.0866e-12f, 6.7044e-12f, 2.9781e-12f, 0), float4(1.0626e-11f, 1.0175e-11f, 4.9261e-12f, 0), float4(2.0988e-12f, 1.9313e-12f, 7.1143e-13f, 0), float4(1.8206e-12f, 1.6640e-12f, 5.8636e-13f, 0),
    float4(5.1012e-12f, 4.7837e-12f, 1.9998e-12f, 0), float4(1.0042e-10f, 1.0116e-10f, 7.4920e-11f, 0), float4(2.2553e-12f, 2.0779e-12f, 7.7190e-13f, 0), float4(1.9898e-11f, 1.9338e-11f, 1.0453e-11f, 0),
    float4(2.6960e-12f, 2.4924e-12f, 9.4661e-13f, 0), float4(9.6588e-12f, 9.2220e-12f, 4.3700e-12f, 0), float4(2.2784e-12f, 2.0996e-12f, 7.8089e-13f, 0), float4(1.4731e-11f, 1.4219e-11f, 7.2985e-12f, 0),
    float4(3.5158e-12f, 3.2682e-12f, 1.2876e-12f, 0), float4(1.4695e-12f, 1.3263e-12f, 4.3121e-13f, 0), float4(1.6033e-12f, 1.4544e-12f, 4.8840e-13f, 0), float4(1.9898e-11f, 1.9339e-11f, 1.0454e-11f, 0),
    float4(5.1458e-12f, 4.8267e-12f, 2.0208e-12f, 0), float4(2.2818e-12f, 2.1028e-12f, 7.8223e-13f, 0), float4(1.5862e-11f, 1.5335e-11f, 7.9676e-12f, 0), float4(8.6375e-12f, 8.2189e-12f, 3.8015e-12f, 0),
    float4(2.7190e-12f, 2.5140e-12f, 9.5588e-13f, 0), float4(2.8202e-12f, 2.6095e-12f, 9.9697e-13f, 0), float4(1.9021e-12f, 1.7430e-12f, 6.2465e-13f, 0), float4(1.2798e-11f, 1.2317e-11f, 6.1842e-12f, 0),
    float4(3.8459e-11f, 3.7947e-11f, 2.3170e-11f, 0), float4(2.4874e-11f, 2.4307e-11f, 1.3712e-11f, 0), float4(2.0839e-12f, 1.9173e-12f, 7.0571e-13f, 0), float4(1.6641e-11f, 1.6107e-11f, 8.4362e-12f, 0),
    float4(2.2050e-12f, 2.0308e-12f, 7.5239e-13f, 0), float4(1.2840e-11f, 1.2359e-11f, 6.2083e-12f, 0), float4(1.3477e-12f, 1.2105e-12f, 3.8133e-13f, 0), float4(2.0210e-12f, 1.8585e-12f, 6.8169e-13f, 0),
    float4(1.1129e-10f, 1.1229e-10f, 8.4571e-11f, 0), float4(1.0729e-11f, 1.0277e-11f, 4.9865e-12f, 0), float4(5.4022e-11f, 5.3730e-11f, 3.5164e-11f, 0), float4(3.3316e-12f, 3.0934e-12f, 1.2092e-12f, 0),
    float4(2.2298e-12f, 2.0541e-12f, 7.6202e-13f, 0), float4(1.7255e-11f, 1.6714e-11f, 8.8089e-12f, 0), float4(7.9351e-11f, 7.9656e-11f, 5.6906e-11f, 0), float4(8.7334e-12f, 8.3129e-12f, 3.8540e-12f, 0),
    float4(1.0792e-10f, 1.0884e-10f, 8.1555e-11f, 0), float4(6.2139e-11f, 6.2013e-11f, 4.1865e-11f, 0), float4(2.0841e-12f, 1.9175e-12f, 7.0578e-13f, 0), float4(3.4203e-11f, 3.3660e-11f, 2.0105e-11f, 0),
    float4(2.1425e-12f, 1.9722e-12f, 7.2824e-13f, 0), float4(8.6091e-11f, 8.6526e-11f, 6.2564e-11f, 0), float4(9.7973e-12f, 9.3583e-12f, 4.4486e-12f, 0), float4(9.9378e-11f, 1.0010e-10f, 7.4006e-11f, 0),
    float4(5.3960e-12f, 5.0675e-12f, 2.1393e-12f, 0), float4(2.3076e-11f, 2.2508e-11f, 1.2511e-11f, 0), float4(8.6217e-12f, 8.2035e-12f, 3.7929e-12f, 0), float4(2.3234e-12f, 2.1419e-12f, 7.9849e-13f, 0),
    float4(4.1597e-12f, 3.8815e-12f, 1.5689e-12f, 0), float4(5.6782e-12f, 5.3396e-12f, 2.2748e-12f, 0), float4(3.5897e-11f, 3.5365e-11f, 2.1313e-11f, 0), float4(4.4197e-12f, 4.1301e-12f, 1.6856e-12f, 0),
    float4(7.1046e-12f, 6.7219e-12f, 2.9873e-12f, 0), float4(3.3687e-10f, 3.4767e-10f, 3.7777e-10f, 0), float4(5.0077e-11f, 4.9716e-11f, 3.2013e-11f, 0), float4(2.3977e-12f, 2.2116e-12f, 8.2767e-13f, 0),
    float4(3.1476e-12f, 2.9190e-12f, 1.1319e-12f, 0), float4(9.4320e-11f, 9.4926e-11f, 6.9606e-11f, 0), float4(5.3127e-12f, 4.9873e-12f, 2.0997e-12f, 0), float4(1.7487e-12f, 1.5944e-12f, 5.5327e-13f, 0),
    float4(1.8264e-11f, 1.7714e-11f, 9.4292e-12f, 0), float4(1.1872e-11f, 1.1408e-11f, 5.6641e-12f, 0), float4(4.9736e-11f, 4.9370e-11f, 3.1744e-11f, 0), float4(4.2559e-12f, 3.9734e-12f, 1.6119e-12f, 0),
    float4(8.0144e-11f, 8.0464e-11f, 5.7567e-11f, 0), float4(2.7541e-11f, 2.6977e-11f, 1.5513e-11f, 0), float4(1.5968e-11f, 1.5440e-11f, 8.0310e-12f, 0), float4(1.0281e-11f, 9.8353e-12f, 4.7260e-12f, 0),
    float4(4.9349e-12f, 4.6239e-12f, 1.9221e-12f, 0), float4(7.4191e-12f, 7.0282e-12f, 3.1505e-12f, 0), float4(1.4122e-12f, 1.2718e-12f, 4.0748e-13f, 0), float4(1.8283e-12f, 1.6714e-12f, 5.8994e-13f, 0),
    float4(7.5045e-11f, 7.5239e-11f, 5.3088e-11f, 0), float4(4.6330e-12f, 4.3344e-12f, 1.7827e-12f, 0), float4(2.1192e-12f, 1.9504e-12f, 7.1928e-13f, 0), float4(2.6343e-11f, 2.5780e-11f, 1.4712e-11f, 0),
    float4(9.8333e-12f, 9.3938e-12f, 4.4691e-12f, 0), float4(1.1293e-11f, 1.0836e-11f, 5.3200e-12f, 0), float4(4.6366e-12f, 4.3377e-12f, 1.7843e-12f, 0), float4(3.5493e-12f, 3.3000e-12f, 1.3019e-12f, 0),
    float4(3.3779e-11f, 3.3234e-11f, 1.9805e-11f, 0), float4(8.9810e-12f, 8.5557e-12f, 3.9905e-12f, 0), float4(4.8706e-12f, 4.5622e-12f, 1.8922e-12f, 0), float4(1.4134e-12f, 1.2729e-12f, 4.0797e-13f, 0),
    float4(3.3396e-10f, 3.4461e-10f, 3.7269e-10f, 0), float4(1.5484e-12f, 1.4018e-12f, 4.6465e-13f, 0), float4(8.8504e-11f, 8.8987e-11f, 6.4614e-11f, 0), float4(4.3561e-12f, 4.0692e-12f, 1.6569e-12f, 0),
    float4(2.3501e-11f, 2.2933e-11f, 1.2793e-11f, 0), float4(3.4919e-12f, 3.2454e-12f, 1.2773e-12f, 0), float4(8.4848e-12f, 8.0693e-12f, 3.7183e-12f, 0), float4(5.6447e-12f, 5.3073e-12f, 2.2586e-12f, 0),
    float4(5.8196e-12f, 5.4762e-12f, 2.3434e-12f, 0), float4(8.1338e-12f, 7.7258e-12f, 3.5287e-12f, 0), float4(4.1154e-12f, 3.8392e-12f, 1.5492e-12f, 0), float4(2.1545e-12f, 1.9835e-12f, 7.3287e-13f, 0),
    float4(6.9162e-12f, 6.5387e-12f, 2.8906e-12f, 0), float4(2.5475e-12f, 2.3525e-12f, 8.8703e-13f, 0), float4(7.7084e-11f, 7.7334e-11f, 5.4921e-11f, 0), float4(8.0999e-11f, 8.1335e-11f, 5.8280e-11f, 0),
    float4(2.2952e-11f, 2.2384e-11f, 1.2429e-11f, 0), float4(1.2002e-11f, 1.1536e-11f, 5.7365e-12f, 0), float4(3.9408e-12f, 3.6726e-12f, 1.4720e-12f, 0), float4(7.8204e-12f, 7.4196e-12f, 3.3615e-12f, 0),
    float4(8.4344e-12f, 8.0199e-12f, 3.6909e-12f, 0), float4(1.5366e-12f, 1.3905e-12f, 4.5958e-13f, 0), float4(6.2789e-11f, 6.2677e-11f, 4.2413e-11f, 0), float4(1.7703e-10f, 1.7993e-10f, 1.4753e-10f, 0),
    float4(5.8544e-12f, 5.5098e-12f, 2.3604e-12f, 0), float4(2.3200e-11f, 2.2632e-11f, 1.2593e-11f, 0), float4(6.4215e-12f, 6.0585e-12f, 2.6404e-12f, 0), float4(2.0113e-12f, 1.8491e-12f, 6.7727e-13f, 0),
    float4(8.3941e-12f, 7.9805e-12f, 3.6691e-12f, 0), float4(1.6353e-11f, 1.5822e-11f, 8.2625e-12f, 0), float4(1.2061e-11f, 1.1594e-11f, 5.7697e-12f, 0), float4(3.0022e-11f, 2.9461e-11f, 1.7193e-11f, 0),
    float4(1.3952e-12f, 1.2555e-12f, 4.0051e-13f, 0), float4(1.7382e-12f, 1.5843e-12f, 5.4848e-13f, 0), float4(1.5853e-11f, 1.5327e-11f, 7.9627e-12f, 0), float4(2.9518e-11f, 2.8957e-11f, 1.6849e-11f, 0),
    float4(3.8046e-12f, 3.5428e-12f, 1.4123e-12f, 0), float4(6.8987e-12f, 6.5218e-12f, 2.8817e-12f, 0), float4(9.1493e-11f, 9.2038e-11f, 6.7171e-11f, 0), float4(4.6725e-12f, 4.3722e-12f, 1.8008e-12f, 0),
    float4(2.9841e-12f, 2.7643e-12f, 1.0641e-12f, 0), float4(9.7136e-12f, 9.2759e-12f, 4.4010e-12f, 0), float4(7.6024e-12f, 7.2068e-12f, 3.2465e-12f, 0), float4(6.0646e-12f, 5.7129e-12f, 2.4633e-12f, 0),
    float4(5.3013e-12f, 4.9763e-12f, 2.0943e-12f, 0), float4(2.0608e-12f, 1.8957e-12f, 6.9688e-13f, 0), float4(8.6554e-11f, 8.6997e-11f, 6.2956e-11f, 0), float4(2.4277e-12f, 2.2398e-12f, 8.3950e-13f, 0),
    float4(5.6332e-12f, 5.2962e-12f, 2.2531e-12f, 0), float4(5.4309e-12f, 5.1011e-12f, 2.1560e-12f, 0), float4(3.5440e-12f, 3.2949e-12f, 1.2996e-12f, 0), float4(2.1105e-12f, 1.9423e-12f, 7.1593e-13f, 0),
    float4(1.2044e-10f, 1.2167e-10f, 9.2877e-11f, 0), float4(2.4473e-11f, 2.3906e-11f, 1.3442e-11f, 0), float4(2.1264e-11f, 2.0699e-11f, 1.1328e-11f, 0), float4(5.0680e-12f, 4.7519e-12f, 1.9843e-12f, 0),
    float4(1.0806e-10f, 1.0898e-10f, 8.1680e-11f, 0), float4(2.1100e-12f, 1.9418e-12f, 7.1573e-13f, 0), float4(4.4033e-12f, 4.1144e-12f, 1.6782e-12f, 0), float4(3.1343e-12f, 2.9064e-12f, 1.1264e-12f, 0),
    float4(1.6992e-12f, 1.5467e-12f, 5.3088e-13f, 0), float4(6.4675e-11f, 6.4607e-11f, 4.4017e-11f, 0), float4(5.2744e-11f, 5.2429e-11f, 3.4135e-11f, 0), float4(1.5308e-12f, 1.3850e-12f, 4.5711e-13f, 0),
    float4(9.7142e-12f, 9.2765e-12f, 4.4013e-12f, 0), float4(2.6055e-11f, 2.5491e-11f, 1.4515e-11f, 0), float4(1.0171e-11f, 9.7262e-12f, 4.6622e-12f, 0), float4(2.5139e-12f, 2.3208e-12f, 8.7363e-13f, 0),
    float4(4.6665e-12f, 4.3664e-12f, 1.7981e-12f, 0), float4(1.3096e-11f, 1.2609e-11f, 6.3534e-12f, 0), float4(3.0090e-10f, 3.0992e-10f, 3.1639e-10f, 0), float4(1.5302e-11f, 1.4782e-11f, 7.6347e-12f, 0),
    float4(1.1167e-11f, 1.0711e-11f, 5.2450e-12f, 0), float4(1.9129e-12f, 1.7535e-12f, 6.2981e-13f, 0), float4(2.7501e-12f, 2.5433e-12f, 9.6846e-13f, 0), float4(6.2248e-12f, 5.8680e-12f, 2.5425e-12f, 0),
    float4(2.6508e-11f, 2.5945e-11f, 1.4825e-11f, 0), float4(5.6008e-11f, 5.5754e-11f, 3.6776e-11f, 0), float4(6.6313e-12f, 6.2621e-12f, 2.7459e-12f, 0), float4(2.2429e-12f, 2.0663e-12f, 7.6707e-13f, 0),
    float4(3.8951e-12f, 3.6291e-12f, 1.4519e-12f, 0), float4(1.0999e-10f, 1.1096e-10f, 8.3407e-11f, 0), float4(2.3815e-12f, 2.1964e-12f, 8.2129e-13f, 0), float4(6.5783e-12f, 6.2106e-12f, 2.7192e-12f, 0),
    float4(1.9778e-12f, 1.8165e-12f, 6.6096e-13f, 0), float4(3.6729e-12f, 3.4175e-12f, 1.3552e-12f, 0), float4(3.4581e-12f, 3.2133e-12f, 1.2629e-12f, 0), float4(3.6416e-11f, 3.5888e-11f, 2.1687e-11f, 0),
    float4(2.0716e-11f, 2.0153e-11f, 1.0975e-11f, 0), float4(5.5768e-12f, 5.2418e-12f, 2.2259e-12f, 0), float4(3.5834e-12f, 3.3324e-12f, 1.3166e-12f, 0), float4(4.8176e-11f, 4.7785e-11f, 3.0521e-11f, 0),
    float4(1.6621e-12f, 1.5110e-12f, 5.1430e-13f, 0), float4(1.7498e-12f, 1.5955e-12f, 5.5375e-13f, 0), float4(1.3587e-11f, 1.3092e-11f, 6.6344e-12f, 0), float4(2.6734e-11f, 2.6171e-11f, 1.4975e-11f, 0),
    float4(4.5090e-11f, 4.4654e-11f, 2.8135e-11f, 0), float4(4.3991e-11f, 4.3541e-11f, 2.7297e-11f, 0), float4(5.0042e-12f, 4.6906e-12f, 1.9544e-12f, 0), float4(2.3439e-11f, 2.2871e-11f, 1.2752e-11f, 0),
    float4(4.0708e-12f, 3.7966e-12f, 1.5294e-12f, 0), float4(1.3803e-11f, 1.3305e-11f, 6.7592e-12f, 0), float4(2.8783e-12f, 2.6643e-12f, 1.0207e-12f, 0), float4(3.4773e-12f, 3.2316e-12f, 1.2711e-12f, 0),
    float4(1.4575e-11f, 1.4066e-11f, 7.2074e-12f, 0), float4(1.6032e-11f, 1.5504e-11f, 8.0697e-12f, 0), float4(5.8710e-11f, 5.8510e-11f, 3.8999e-11f, 0), float4(6.2719e-12f, 5.9136e-12f, 2.5659e-12f, 0),
    float4(2.2210e-11f, 2.1642e-11f, 1.1942e-11f, 0), float4(1.3702e-12f, 1.2318e-12f, 3.9035e-13f, 0), float4(5.9023e-12f, 5.5560e-12f, 2.3837e-12f, 0), float4(9.2867e-11f, 9.3441e-11f, 6.8352e-11f, 0),
    float4(2.4954e-11f, 2.4387e-11f, 1.3766e-11f, 0), float4(3.6363e-12f, 3.3827e-12f, 1.3394e-12f, 0), float4(2.1819e-12f, 2.0091e-12f, 7.4343e-13f, 0), float4(4.7828e-12f, 4.4780e-12f, 1.8516e-12f, 0),
    float4(3.3935e-12f, 3.1521e-12f, 1.2355e-12f, 0), float4(5.8356e-12f, 5.4916e-12f, 2.3512e-12f, 0), float4(6.6974e-12f, 6.3262e-12f, 2.7794e-12f, 0), float4(3.8152e-10f, 3.9420e-10f, 4.5732e-10f, 0),
    float4(1.3006e-11f, 1.2521e-11f, 6.3022e-12f, 0), float4(1.6604e-12f, 1.5094e-12f, 5.1355e-13f, 0), float4(1.6512e-12f, 1.5005e-12f, 5.0948e-13f, 0), float4(6.8678e-11f, 6.8707e-11f, 4.7467e-11f, 0),
    float4(2.4993e-12f, 2.3071e-12f, 8.6784e-13f, 0), float4(8.1901e-12f, 7.7808e-12f, 3.5590e-12f, 0), float4(6.7743e-12f, 6.4008e-12f, 2.8183e-12f, 0), float4(2.2505e-12f, 2.0734e-12f, 7.7003e-13f, 0),
    float4(3.5947e-11f, 3.5416e-11f, 2.1349e-11f, 0), float4(2.2038e-12f, 2.0297e-12f, 7.5191e-13f, 0), float4(1.0652e-11f, 1.0201e-11f, 4.9415e-12f, 0), float4(1.7462e-10f, 1.7745e-10f, 1.4509e-10f, 0),
    float4(3.3359e-11f, 3.2811e-11f, 1.9509e-11f, 0), float4(2.2768e-11f, 2.2200e-11f, 1.2308e-11f, 0), float4(3.1461e-12f, 2.9176e-12f, 1.1313e-12f, 0), float4(2.8683e-12f, 2.6548e-12f, 1.0166e-12f, 0),
    float4(5.3546e-12f, 5.0276e-12f, 2.1196e-12f, 0), float4(1.7353e-12f, 1.5815e-12f, 5.4719e-13f, 0), float4(8.6123e-12f, 8.1942e-12f, 3.7878e-12f, 0), float4(1.7453e-11f, 1.6911e-11f, 8.9301e-12f, 0),
    float4(7.9032e-12f, 7.5005e-12f, 3.4055e-12f, 0), float4(2.9205e-11f, 2.8643e-11f, 1.6635e-11f, 0), float4(3.1157e-11f, 3.0600e-11f, 1.7974e-11f, 0), float4(2.6150e-12f, 2.4160e-12f, 9.1402e-13f, 0),
    float4(2.8861e-12f, 2.6717e-12f, 1.0239e-12f, 0), float4(2.3069e-11f, 2.2501e-11f, 1.2507e-11f, 0), float4(7.9393e-11f, 7.9699e-11f, 5.6942e-11f, 0), float4(1.5700e-12f, 1.4225e-12f, 4.7394e-13f, 0),
    float4(9.0967e-11f, 9.1501e-11f, 6.6719e-11f, 0), float4(2.6997e-11f, 2.6434e-11f, 1.5150e-11f, 0), float4(2.3811e-11f, 2.3242e-11f, 1.2999e-11f, 0), float4(3.7616e-12f, 3.5019e-12f, 1.3936e-12f, 0),
    float4(5.0271e-12f, 4.7126e-12f, 1.9651e-12f, 0), float4(8.9046e-11f, 8.9540e-11f, 6.5076e-11f, 0), float4(1.9303e-12f, 1.7703e-12f, 6.3808e-13f, 0), float4(3.2975e-11f, 3.2426e-11f, 1.9240e-11f, 0),
    float4(1.3327e-11f, 1.2836e-11f, 6.4852e-12f, 0),
};
// END BAKED

// ---------------------------------------------------------------------------------------------
// State layout: three blocks of DATA_W x DATA_H, row 0 of each = the north edge.
//   block 0: Halpha (erg/s/cm2/sr), [O III], front depth z_f (pc), vertical flow scale Rv (pc)
//   block 1: [N II] 6584, [S II] 6731, [O I] 6300, Veil c(Hbeta)  (partner lines added in draw)
//   block 2: front normal (x west, y north, z toward us), [S II] 6716/6731 from the density
// ---------------------------------------------------------------------------------------------

static float bsp(int j, float t) {   // uniform cubic B-spline weights
    const float s = 1.0f - t;
    return j == 0 ? s * s * s / 6.0f
         : j == 1 ? (3.0f * t * t * t - 6.0f * t * t + 4.0f) / 6.0f
         : j == 2 ? (-3.0f * t * t * t + 3.0f * t * t + 3.0f * t + 1.0f) / 6.0f
         : t * t * t / 6.0f;
}
static float dbsp(int j, float t) {
    const float s = 1.0f - t;
    return j == 0 ? -0.5f * s * s
         : j == 1 ? (9.0f * t * t - 12.0f * t) / 6.0f
         : j == 2 ? (-9.0f * t * t + 6.0f * t + 3.0f) / 6.0f
         : 0.5f * t * t;
}

// Front depth and slope (dz/dx, dz/dy in pc/pc) at map texel (col, row), row 0 = south.
static float3 front_at(float col, float row) {
    const int KX = 15, KY = 13;
    const float u = (col + 0.5f) / float(DATA_W) * float(KX - 3);
    const float v = (row + 0.5f) / float(DATA_H) * float(KY - 3);
    const int iu = clamp(int(floor(u)), 0, KX - 4), iv = clamp(int(floor(v)), 0, KY - 4);
    const float tu = u - float(iu), tv = v - float(iv);
    float z = 0.0f, zu = 0.0f, zv = 0.0f;
    for (int b = 0; b < 4; b++) {
        float rz = 0.0f, rzu = 0.0f;
        for (int a = 0; a < 4; a++) {
            const float p = FRONT_P[iv + b][iu + a];
            rz += bsp(a, tu) * p;
            rzu += dbsp(a, tu) * p;
        }
        z += bsp(b, tv) * rz;
        zu += bsp(b, tv) * rzu;
        zv += dbsp(b, tv) * rz;
    }
    const float su = float(KX - 3) / (float(DATA_W) * TEXEL_PC), sv = float(KY - 3) / (float(DATA_H) * TEXEL_PC);
    return float3(z, zu * su, zv * sv);
}

static float dec_log(float e, int k) { return pow(10.0f, mix(LOG_RANGE[k].x, LOG_RANGE[k].y, e)); }

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       texture2d<float, access::read> data [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const uint blk = gid.y / DATA_H, jn = gid.y - blk * DATA_H;   // jn: 0 = north
    if (blk == 3u && jn == 0u) {   // the flow profile row, sampled with hardware interpolation
        state.write(gid.x < 64u ? float4(FLOW_CDF[gid.x], FLOW_PDF[gid.x], 0.0f, 0.0f) : float4(0.0f), gid);
        return;
    }
    if (blk > 2u || gid.x >= DATA_W) { state.write(float4(0.0f), gid); return; }
    const float4 A = data.read(uint2(gid.x, jn));
    const float4 B = data.read(uint2(gid.x, jn + DATA_H));
    const float row = float(DATA_H - 1u - jn);
    const float3 fr = front_at(float(gid.x), row);
    const float3 n = normalize(float3(-fr.y, -fr.z, 1.0f));
    float4 o;
    if (blk == 0u) {
        const float R0 = dec_log(B.z, 5);
        o = float4(dec_log(A.x, 0), dec_log(A.y, 1), fr.x, R0 / n.z);
    } else if (blk == 1u) {
        o = float4(dec_log(A.z, 2), dec_log(A.w, 3), dec_log(B.x, 4), B.y * 1.6f);
    } else {
        o = float4(n, mix(0.4f, 1.5f, B.w));   // 6716/6731 from the measured density
    }
    state.write(o, gid);
}

// ---------------------------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------------------------
struct View { float3x3 R; float3 d; float scale; float2 half_px; };

static View make_view(constant ArgusFrame& f) {
    const float ph = 6.2831853f * f.time / ORBIT_T;
    const float yaw = ORBIT_YAW * sin(ph), pitch = ORBIT_PITCH * sin(ph * 0.5f);   // both 0 at t = 0
    const float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    // camera axes in nebula coordinates: right, up, back (toward the camera)
    const float3x3 Ry = float3x3(float3(cy, 0, -sy), float3(0, 1, 0), float3(sy, 0, cy));
    const float3x3 Rx = float3x3(float3(1, 0, 0), float3(0, cp, sp), float3(0, -sp, cp));
    View v;
    v.R = Ry * Rx;
    v.d = -v.R[2];
    v.scale = min(VIEW_W_PC / float(f.width), VIEW_H_PC / float(f.height));   // pc per pixel: any screen shape stays inside the data
    v.half_px = 0.5f * float2(f.width, f.height);
    return v;
}

// pc (x west, y north) -> state texture coordinate of block `blk`
static float2 st_uv(float2 xy, uint blk) {
    float col = STAR_C_TEX.x + xy.x / TEXEL_PC;
    float row = STAR_C_TEX.y + xy.y / TEXEL_PC;
    col = clamp(col, 0.5f, float(DATA_W) - 1.5f);
    row = clamp(row, 0.5f, float(DATA_H) - 1.5f);
    const float jn = float(DATA_H) - 1.0f - row;
    return float2((col + 0.5f) / float(DATA_W), (jn + 0.5f + float(blk * DATA_H)) / float(3u * DATA_H + 1u));
}

// The flow's emission profile, u = h / R0 over 0..3: CDF in .x, PDF in .y (state's last row).
static float2 flow_prof(texture2d<float> st, sampler smp, float u) {
    const float x = (clamp(u, 0.0f, 3.0f) * (63.0f / 3.0f) + 0.5f) / float(DATA_W);
    const float2 p = st.sample(smp, float2(x, (float(3u * DATA_H) + 0.5f) / float(3u * DATA_H + 1u))).xy;
    return float2(p.x, u > 3.0f ? 0.0f : p.y);
}

// Colour of one mapped line group after the Veil and the ISM: sum over its lines of
// XYZ x ratio x 10^(-c k).
static float3 group_xyz(constant Line* L, int n, float c, float r_override) {
    float3 s = 0.0f;
    for (int i = 0; i < n; i++) {
        const float ratio = L[i].ratio < 0.0f ? r_override : L[i].ratio;
        s += L[i].xyz * ratio * exp(-2.3025851f * c * L[i].k);
    }
    return s;
}

static float3 xyz_to_srgb_lin(float3 c) {
    return float3(3.2406f * c.x - 1.5372f * c.y - 0.4986f * c.z,
                  -0.9689f * c.x + 1.8758f * c.y + 0.0415f * c.z,
                  0.0557f * c.x - 0.2040f * c.y + 1.0570f * c.z);
}

// Out-of-gamut colours: keep the luminance and the hue and compress the saturation. e is how
// far the colour reaches toward the sRGB boundary (1 = on it); saturations above half the way
// to the boundary are compressed smoothly so the purest lines end at 0.75 of it (a display
// choice: a screen at its gamut edge reads as neon, which the nebula is not).
static float3 gamut(float3 rgb) {
    const float Y = max(dot(rgb, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f);
    const float m = min(rgb.x, min(rgb.y, rgb.z));
    const float e = (Y - m) / max(Y, 1e-12f);   // 1 / (largest in-gamut saturation scale)
    if (e <= 0.5f) return max(rgb, 0.0f);
    const float ec = 0.5f + 0.25f * tanh((e - 0.5f) / 0.25f);
    return max(Y + (rgb - Y) * (ec / e), 0.0f);
}

// Display: an asinh stretch of luminance (how nebulae are shown: it keeps both the faint
// outskirts and the bright core), the same factor on all three channels so hues stay put,
// then colours brighter than the screen fade to white instead of clipping.
static float3 stretch(float3 rgb) {
    rgb = max(gamut(rgb), 0.0f);
    const float L = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
    const float k = asinh(L / STRETCH) / (asinh(1.0f / STRETCH) * max(L, 1e-12f));
    rgb *= k;
    const float m = max(rgb.x, max(rgb.y, rgb.z));
    if (m > 1.0f) rgb = mix(rgb / m, float3(1.0f), 1.0f - 1.0f / m);
    return saturate(rgb);
}

constant uint SCAP = 96u;

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> st [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tpos [[thread_position_in_threadgroup]],
                       uint2 tsize [[threads_per_threadgroup]],
                       uint tidx [[thread_index_in_threadgroup]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    threadgroup float4 sP[SCAP];   // screen x, y, 1/(2 sigma^2) unused, radius
    threadgroup float4 sC[SCAP];   // linear XYZ radiance scale per pixel
    threadgroup atomic_uint nS;

    const View V = make_view(f);
    if (tidx == 0) atomic_store_explicit(&nS, 0u, memory_order_relaxed);
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // ---- stars: each thread projects a few, keeps those touching this tile ----
    const float2 tlo = float2(gid - tpos), thi = tlo + float2(tsize);
    const uint nthreads = tsize.x * tsize.y;
    const float px_sr = (V.scale / DIST_PC) * (V.scale / DIST_PC);   // sr per pixel
    for (uint i = tidx; i < N_STARS; i += nthreads) {
        const float4 s = STARS[i];
        const float3 p = float3(s.xy, s.z) - float3(VIEW_C, PIVOT_Z);
        const float2 sc = float2(dot(p, V.R[0]), dot(p, V.R[1])) / V.scale;
        const float2 pp = float2(V.half_px.x + sc.x, V.half_px.y - sc.y);
        // hidden behind the front (inside the molecular cloud)?
        const float zf = st.sample(smp, st_uv(s.xy, 0u)).z;
        if (s.z < zf) continue;
        const float3 xyz = STAR_XYZ[i].xyz;
        const float peak = xyz.y / px_sr;              // radiance if all its light fell in one pixel
        const float rad = clamp(1.5f + 2.0f * log2(max(peak * EXPOSURE / STRETCH, 1.0f)), 2.0f, 40.0f);
        if (pp.x + rad < tlo.x || pp.x - rad > thi.x || pp.y + rad < tlo.y || pp.y - rad > thi.y) continue;
        const uint slot = atomic_fetch_add_explicit(&nS, 1u, memory_order_relaxed);
        if (slot >= SCAP) continue;
        const float c = st.sample(smp, st_uv(s.xy + V.d.xy * ((D_VEIL - s.z) / max(-V.d.z, 0.2f)), 1u)).w + C_FG;
        // stars are dimmed at their own colour: X ~ 600 nm, Y ~ 555 nm, Z ~ 450 nm
        const float3 T = exp(-2.3025851f * c * STAR_K);
        sP[slot] = float4(pp, 0.0f, rad);
        sC[slot] = float4(xyz * T / px_sr, 0.0f);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x >= f.width || gid.y >= f.height) return;

    // ---- this pixel's ray ----
    const float2 sp = (float2(gid) + 0.5f - V.half_px) * float2(1.0f, -1.0f) * V.scale;
    const float3 o = float3(VIEW_C, PIVOT_Z) + V.R[0] * sp.x + V.R[1] * sp.y;   // on the plane through the pivot
    const float3 d = V.d;                                                      // toward the cloud
    const float dz = d.z;                                                      // < 0

    // 1) where the ray meets the front: coarse march in z from above the highest front point.
    float tA = (FRONT_ZMAX + 0.01f - o.z) / dz, tB = (FRONT_ZMIN - 0.01f - o.z) / dz;
    float t_hit = tB;
    {
        float tp = tA;
        float gp = (o.z + tp * dz) - st.sample(smp, st_uv(o.xy + tp * d.xy, 0u)).z;
        const int N = 10;
        for (int k = 1; k <= N; k++) {
            const float t = mix(tA, tB, float(k) / float(N));
            const float g = (o.z + t * dz) - st.sample(smp, st_uv(o.xy + t * d.xy, 0u)).z;
            if (g <= 0.0f) {
                float lo = tp, hi = t;
                for (int b = 0; b < 5; b++) {
                    const float m = 0.5f * (lo + hi);
                    const float gm = (o.z + m * dz) - st.sample(smp, st_uv(o.xy + m * d.xy, 0u)).z;
                    if (gm <= 0.0f) hi = m; else lo = m;
                }
                t_hit = 0.5f * (lo + hi);
                break;
            }
            tp = t; gp = g;
        }
    }

    // 2) the flow, from the front back toward the camera: steps grow geometrically away from
    //    the front; each segment is integrated exactly for its own front height (CDF). What
    //    lies beyond the last step is added at the last step's brightness, so a ray from
    //    Earth always gets exactly the measured line brightness.
    float I_ha = 0.0f, I_o3 = 0.0f;
    {
        float t0 = t_hit;
        float4 s0 = st.sample(smp, st_uv(o.xy + t0 * d.xy, 0u));
        float v0 = max((o.z + t0 * dz - s0.z) / max(s0.w, 1e-4f), 0.0f);
        float step = 0.005f;
        float P0 = flow_prof(st, smp, v0).x;
        for (int k = 0; k < 8; k++) {
            const float t1 = t0 - step / max(-dz, 0.3f);
            const float4 s1 = st.sample(smp, st_uv(o.xy + t1 * d.xy, 0u));
            const float Rv = max(0.5f * (s0.w + s1.w), 1e-4f);
            const float v1 = max((o.z + t1 * dz - s1.z) / max(s1.w, 1e-4f), 0.0f);
            const float dl = abs(t0 - t1);
            const float dv = v1 - v0;
            const float2 p1 = flow_prof(st, smp, v1);
            const float avg = abs(dv) > 1e-3f ? (p1.x - P0) / dv : flow_prof(st, smp, 0.5f * (v0 + v1)).y;
            const float w = avg * dl / Rv;
            I_ha += w * 0.5f * (s0.x + s1.x);
            I_o3 += w * 0.5f * (s0.y + s1.y);
            t0 = t1; s0 = s1; v0 = v1; P0 = p1.x; step *= 1.75f;
            if (v1 >= 3.0f) break;
        }
        const float tail = 1.0f - P0;
        I_ha += tail * s0.x;
        I_o3 += tail * s0.y;
    }

    // 3) the front sheet ([N II], [S II], [O I]) seen at its angle
    const float2 hit_xy = o.xy + t_hit * d.xy;
    const float4 sheet = st.sample(smp, st_uv(hit_xy, 1u));
    const float4 nb = st.sample(smp, st_uv(hit_xy, 2u));
    const float3 nrm = nb.xyz;
    const float graze = min(nrm.z / max(abs(dot(nrm, d)), 1e-3f), GRAZE_MAX);

    // 4) the Veil and the ISM in front
    const float t_veil = (D_VEIL - o.z) / dz;
    const float c_veil = st.sample(smp, st_uv(o.xy + t_veil * d.xy, 1u)).w;
    const float c = c_veil + C_FG;

    float3 rgb;
    if (PALETTE == 0) {
        float3 xyz = I_ha * group_xyz(L_BALMER, 4, c, 0.0f)
                   + I_o3 * group_xyz(L_OIII, 2, c, 0.0f)
                   + graze * (sheet.x * group_xyz(L_NII, 2, c, 0.0f)
                            + sheet.y * group_xyz(L_SII, 2, c, nb.w)
                            + sheet.z * group_xyz(L_OI, 2, c, 0.0f));
        rgb = xyz_to_srgb_lin(xyz) * EXPOSURE;
    } else {
        // Hubble SHO: [S II] -> red, Halpha -> green, [O III] -> blue, each scaled to its own range
        const float3 sho = float3(graze * sheet.y * (1.0f + nb.w) * exp(-2.3025851f * c * L_SII[0].k) / SHO_NORM.x,
                                  I_ha * exp(-2.3025851f * c * L_BALMER[0].k) / SHO_NORM.y,
                                  I_o3 * exp(-2.3025851f * c * L_OIII[0].k) / SHO_NORM.z);
        rgb = sho;
    }

    // 5) stars
    const uint ns = min(atomic_load_explicit(&nS, memory_order_relaxed), SCAP);
    const float2 pc = float2(gid) + 0.5f;
    float3 star = 0.0f;
    for (uint j = 0; j < ns; j++) {
        const float4 P = sP[j];
        const float2 dd = pc - P.xy;
        const float r2 = dot(dd, dd);
        if (r2 > P.w * P.w) continue;
        // a telescope's star image: Gaussian core (sigma 0.8 px) + a faint wide wing
        const float psf = 0.2487f * exp(-r2 * 0.78125f) + 0.0025f / (1.0f + r2 * 0.1f) / (1.0f + r2 * 0.1f);
        star += sC[j].xyz * psf;
    }
    rgb += xyz_to_srgb_lin(star) * EXPOSURE;

    out.write(float4(argus_srgb(stretch(rgb)), 1.0f), gid);
}
