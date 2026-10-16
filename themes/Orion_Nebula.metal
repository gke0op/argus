// ============================================================================
// ORION NEBULA // themes/Orion_Nebula.metal
// Author: Claude Opus (Anthropic), 2026-10-16.
//
// The heart of the Orion Nebula (M42, the Huygens region, 0.68 x 0.57 pc), built from
// what telescopes measured of it and a model of the physics that makes it shine,
// fitted to those measurements. Seen from Earth it is the measured nebula; as the
// view swings a few degrees round it, the 3D shape behind that image appears.
//
// MEASURED (the shipped data, themes/Orion_Nebula.bin):
//  * Line brightness of Halpha, [O III] 5007, [N II] 6584, [S II] 6731 and [O I] 6300 over
//    the whole field, corrected for dust, and the dust reddening c(Hbeta) itself: VLT/MUSE,
//    Weilbacher et al. 2015, A&A 582, A114 (data doi:10.17876/data/2023_3, CC0).
//    Downsampled 3x to 0.6" texels and 8-bit log-encoded (encoding error < 1%), bright
//    stars masked, and the instrument's slicer stripes (1.5-3.7%) removed. Halpha is their
//    dereddened Hbeta x 2.89, the Case-B ratio they dereddened with.
//  * [S II] electron density, and the line-of-sight velocities of Halpha, [N II] and
//    [S II] from the same data (used by the fit, not shipped).
//  * Positions and V magnitudes of the 12 brightest stars in the field (SIMBAD), and
//    temperatures of the Trapezium and theta2 stars (Simon-Diaz et al. 2006). Their V is as
//    observed, so the bake removes the measured reddening at each star (theta1 Ori C:
//    A_V 1.85) and the draw puts it back as seen from wherever the view is.
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
//    found 0.2 pc at their 440 pc, 0.18 pc at ours. It is domed toward the Trapezium
//    and deepens away from it (a mildly convex front, the shape Henney et al. 2005 found
//    fits Orion), tilted 23 deg (median) from the line of sight.
//  * The ionised gas: a photoevaporation flow off the front, isothermal and sonic at
//    the front (Henney, Arthur & Garcia-Diaz 2005), so density and speed fall and rise
//    with height. Its thickness comes from the measured emission measure and [S II]
//    density, with one density factor fitted so it matches the front's curvature: the
//    flow needs 2.25x the [S II] density at the front (the [Cl III] density, from gas
//    nearer the front, reads 1.64x; so the flow's thickness is known to ~2x).
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
//  * The Veil is a thin screen 1 pc in front of theta1 Ori C (published: 0.4 pc, van der
//    Werf et al. 2013, to 1-3 pc, Abel et al. 2004).
//  * Fainter cluster stars: positions and brightnesses are statistical, drawn from the
//    measured structure of the Orion Nebula Cluster (rho ~ r^-2.2, Da Rio et al. 2014;
//    core radius 0.16-0.21 pc, Hillenbrand & Hartmann 1998; ellipticity 0.3) and the
//    Kroupa 2001 mass function, with rough 1 Myr
//    pre-main-sequence luminosities and blackbody spectra. Only the 12 bright stars are real.
//  * Camera: orthographic (we are 400 pc away), an exposure, an asinh stretch and a soft
//    star image (a telescope's, not an eye's). It starts on Earth's line of sight, where
//    it shows the measured maps (median 0.25/255 of a display level off them, 99% within
//    0.8/255: tools/orion_bake/verify_earth_view.py), then swings slowly up to 2.4 deg
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
// ISM, and adds stars culled per threadgroup tile. No argus_step: the state never changes.
//
// @argus state 588x1477
// @argus data Orion_Nebula.bin 588x984 rgba8
// ============================================================================

constant int   PALETTE   = 0;        // 0 = true colour, 1 = Hubble SHO false colour (labelled)
constant float D_VEIL    = 1.0f;     // pc in front of theta1 Ori C (O'Dell et al. 2009)
constant float VIEW_W_PC = 0.60f;    // field of view across the screen's width...
constant float VIEW_H_PC = 0.50f;    // ...or its height, whichever is tighter. The data are 0.68 x 0.57 pc;
                                     // with the yaw below, the Veil (1.1 pc above the pivot) stays within
                                     // 4 mpc of the data at full swing (1.1 x tan 2.4 deg = 0.046 pc)
constant float2 VIEW_C   = float2(-0.015f, -0.045f);   // view centre, pc from theta1 Ori C (west, north)
constant float ORBIT_YAW = 0.042f;   // radians (2.4 deg)
constant float ORBIT_PITCH = 0.035f; // radians (2.0 deg)
constant float EDGE_TEX  = 12.0f;    // the gas fades out over the last 12 texels (0.014 pc) of the data
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
constant float FLOW_TAIL[64] = {  // E[h/R0 | above h/R0 = 3 i / 63]
    0.262468f, 0.342582f, 0.413907f, 0.481987f, 0.548015f, 0.612496f, 0.675698f, 0.737774f, 0.798821f, 0.858903f, 0.918064f, 0.976332f, 1.033732f, 1.090277f, 1.145982f, 1.200854f, 1.254904f, 1.308137f, 1.360559f, 1.412177f, 1.462996f, 1.513022f, 1.562260f, 1.610717f, 1.658398f, 1.705309f, 1.751458f, 1.796851f, 1.841495f, 1.885398f, 1.928567f, 1.971010f, 2.012736f, 2.053752f, 2.094068f, 2.133691f, 2.172632f, 2.210898f, 2.248500f, 2.285446f, 2.321745f, 2.357408f, 2.392443f, 2.426861f, 2.460670f, 2.493880f, 2.526502f, 2.558543f, 2.590015f, 2.620926f, 2.651286f, 2.681104f, 2.710390f, 2.739154f, 2.767403f, 2.795147f, 2.822396f, 2.849158f, 2.875443f, 2.901258f, 2.926613f, 2.951516f, 2.975976f, 3.000000f};
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
constant uint N_STARS = 570u;
constant float4 STARS[N_STARS] = {   // x, y, z (pc from theta1 Ori C: west, north, toward us); first 12 real
    float4(0.0000f, 0.0000f, 0.0000f, 0),   // theta1 Ori C
    float4(-0.2877f, -0.1898f, 0.0000f, 0),   // theta2 Ori B
    float4(-0.1864f, -0.1841f, 0.0000f, 0),   // theta2 Ori A
    float4(-0.0229f, 0.0123f, 0.0000f, 0),   // theta1 Ori D
    float4(0.0186f, 0.0167f, 0.0000f, 0),   // theta1 Ori A
    float4(0.0096f, 0.0313f, 0.0000f, 0),   // theta1 Ori B
    float4(-0.3463f, -0.3441f, 0.0000f, 0),   // V1073 Ori
    float4(-0.1232f, 0.1912f, 0.0000f, 0),   // V1230 Ori
    float4(-0.0076f, -0.0044f, 0.0000f, 0),   // theta1 Ori F
    float4(0.4731f, -0.2197f, 0.0000f, 0),   // KS Ori
    float4(-0.0148f, 0.1892f, 0.0000f, 0),   // MR Ori
    float4(0.3136f, -0.2261f, 0.0000f, 0),   // LL Ori
    float4(0.1671f, -0.1100f, 0.3654f, 0), float4(-0.0522f, -0.0127f, 0.2342f, 0), float4(0.0758f, 0.0658f, 0.0828f, 0), float4(-0.0906f, 0.0942f, 0.5716f, 0),
    float4(0.0944f, 0.1172f, -0.4308f, 0), float4(0.1699f, -0.1446f, -0.2276f, 0), float4(-0.0143f, -0.0069f, -0.0639f, 0), float4(-0.0162f, -0.0080f, 0.6516f, 0),
    float4(0.2253f, -0.2085f, 0.2220f, 0), float4(-0.3101f, 0.1619f, -0.1280f, 0), float4(-0.2098f, -0.1273f, -0.6002f, 0), float4(-0.1491f, 0.0254f, 0.1037f, 0),
    float4(-0.1208f, 0.1280f, -0.0224f, 0), float4(-0.0327f, 0.1931f, -0.1874f, 0), float4(0.0588f, 0.1291f, 0.0418f, 0), float4(-0.3099f, -0.2404f, 0.0014f, 0),
    float4(0.2311f, -0.0888f, -0.1973f, 0), float4(-0.0983f, -0.1875f, -0.2114f, 0), float4(0.1768f, -0.2469f, -0.1290f, 0), float4(-0.3478f, -0.1630f, -0.0076f, 0),
    float4(-0.0716f, 0.1066f, 0.0252f, 0), float4(-0.1787f, -0.2210f, -0.3428f, 0), float4(-0.1251f, -0.0333f, -0.4108f, 0), float4(0.2782f, 0.1817f, 0.1827f, 0),
    float4(-0.2971f, 0.0609f, 0.1529f, 0), float4(0.0214f, 0.1141f, 0.1782f, 0), float4(0.0788f, 0.1959f, -0.3561f, 0), float4(-0.2759f, 0.0797f, 0.2033f, 0),
    float4(0.0050f, -0.0004f, 0.7949f, 0), float4(-0.0526f, 0.1965f, 0.0442f, 0), float4(0.2043f, 0.1083f, -0.1042f, 0), float4(0.2715f, -0.1265f, -0.1056f, 0),
    float4(-0.0681f, -0.0203f, 0.1656f, 0), float4(-0.0413f, -0.2478f, 0.1717f, 0), float4(-0.0824f, -0.0483f, -0.3143f, 0), float4(-0.3304f, -0.0414f, -0.0996f, 0),
    float4(0.0350f, -0.2080f, 0.0261f, 0), float4(-0.0171f, 0.2069f, 0.6407f, 0), float4(0.0086f, 0.1962f, 0.0920f, 0), float4(0.2606f, 0.1303f, 0.0227f, 0),
    float4(-0.0854f, 0.1307f, 0.0147f, 0), float4(0.1550f, 0.0540f, 0.6644f, 0), float4(-0.1625f, -0.1653f, 0.1253f, 0), float4(-0.0110f, 0.0888f, -0.2006f, 0),
    float4(-0.2699f, 0.0018f, -0.2960f, 0), float4(0.2896f, -0.1502f, -0.4341f, 0), float4(0.2526f, 0.1648f, -0.0436f, 0), float4(-0.0596f, -0.2557f, 0.3389f, 0),
    float4(-0.3467f, 0.0429f, 0.0433f, 0), float4(-0.1484f, -0.1828f, 0.2914f, 0), float4(-0.0426f, 0.1276f, 0.0211f, 0), float4(0.2610f, -0.1913f, 0.6327f, 0),
    float4(-0.2616f, 0.1084f, -0.5341f, 0), float4(0.0297f, 0.1906f, -0.6675f, 0), float4(-0.0633f, 0.1322f, 0.0476f, 0), float4(-0.3627f, -0.2754f, -0.6158f, 0),
    float4(-0.1961f, 0.0852f, -0.6162f, 0), float4(-0.1064f, -0.0962f, -0.1687f, 0), float4(-0.1118f, -0.1753f, 0.1278f, 0), float4(-0.3438f, 0.0965f, -0.0616f, 0),
    float4(0.0253f, -0.0563f, 0.0517f, 0), float4(-0.3002f, 0.1107f, -0.4204f, 0), float4(-0.0703f, -0.2733f, 0.4895f, 0), float4(-0.1326f, 0.1544f, 0.2384f, 0),
    float4(0.0721f, 0.0793f, -0.1919f, 0), float4(-0.0794f, 0.1165f, -0.2979f, 0), float4(0.3052f, -0.0313f, -0.6348f, 0), float4(0.1463f, -0.1922f, 0.0209f, 0),
    float4(0.0875f, -0.0531f, -0.1517f, 0), float4(0.3000f, 0.1424f, 0.0869f, 0), float4(-0.0919f, 0.1618f, -0.2217f, 0), float4(0.1041f, 0.1491f, -0.1246f, 0),
    float4(0.0734f, -0.0326f, 0.4462f, 0), float4(0.2981f, -0.0882f, 0.3906f, 0), float4(0.1092f, -0.1333f, -0.4370f, 0), float4(-0.1366f, -0.0988f, 0.0347f, 0),
    float4(0.1156f, -0.1428f, -0.5316f, 0), float4(-0.1883f, 0.2054f, 0.2069f, 0), float4(0.0224f, -0.1639f, 0.1699f, 0), float4(-0.1238f, 0.1502f, -0.3070f, 0),
    float4(-0.2320f, -0.1868f, -0.0447f, 0), float4(0.2721f, 0.1333f, -0.0836f, 0), float4(0.2439f, -0.0599f, -0.2418f, 0), float4(0.0500f, 0.0118f, -0.6009f, 0),
    float4(0.0441f, -0.0532f, -0.0119f, 0), float4(0.2127f, 0.0612f, 0.0208f, 0), float4(0.0231f, -0.0456f, 0.3790f, 0), float4(0.0983f, 0.2095f, -0.4972f, 0),
    float4(0.2708f, 0.1834f, -0.4071f, 0), float4(-0.0479f, 0.1420f, -0.0570f, 0), float4(-0.3573f, 0.1595f, 0.7760f, 0), float4(0.2175f, 0.1957f, 0.0188f, 0),
    float4(-0.0917f, 0.1645f, -0.1757f, 0), float4(-0.0421f, -0.2286f, -0.0786f, 0), float4(0.0886f, -0.2580f, 0.1600f, 0), float4(-0.1823f, -0.1549f, -0.0799f, 0),
    float4(-0.0371f, -0.2223f, 0.0728f, 0), float4(0.0575f, -0.1348f, -0.0209f, 0), float4(0.2401f, -0.2382f, -0.3237f, 0), float4(-0.0379f, -0.2352f, 0.1274f, 0),
    float4(-0.1493f, 0.0164f, 0.0042f, 0), float4(0.0123f, -0.3035f, 0.3206f, 0), float4(0.2177f, -0.1601f, -0.3430f, 0), float4(-0.0437f, -0.0324f, 0.0038f, 0),
    float4(-0.1353f, 0.1466f, -0.0954f, 0), float4(0.0985f, 0.1231f, -0.1435f, 0), float4(0.1657f, -0.2605f, 0.5396f, 0), float4(-0.0661f, 0.0892f, -0.4487f, 0),
    float4(0.2963f, 0.0043f, 0.1683f, 0), float4(0.1309f, -0.0686f, -0.1902f, 0), float4(-0.2562f, 0.1950f, 0.1114f, 0), float4(-0.1658f, -0.1432f, -0.5130f, 0),
    float4(-0.1809f, -0.0790f, -0.6813f, 0), float4(0.2374f, 0.0213f, -0.0778f, 0), float4(-0.1366f, -0.2050f, -0.2852f, 0), float4(0.0898f, 0.0926f, 0.1550f, 0),
    float4(-0.0007f, 0.0317f, 0.0065f, 0), float4(-0.2682f, -0.1985f, -0.0956f, 0), float4(-0.0085f, -0.2471f, -0.5521f, 0), float4(-0.3275f, -0.2148f, -0.4284f, 0),
    float4(0.2554f, 0.1005f, 0.1241f, 0), float4(-0.0606f, 0.1803f, -0.2964f, 0), float4(0.0544f, 0.0889f, -0.4180f, 0), float4(0.0749f, -0.0970f, -0.2159f, 0),
    float4(-0.0152f, 0.1207f, -0.0938f, 0), float4(0.1040f, 0.0525f, 0.1547f, 0), float4(-0.0462f, 0.1872f, -0.1117f, 0), float4(-0.2152f, 0.0359f, 0.1753f, 0),
    float4(-0.2696f, 0.2068f, -0.1701f, 0), float4(0.0280f, 0.0609f, 0.3636f, 0), float4(-0.0935f, -0.2673f, 0.4653f, 0), float4(0.0630f, -0.1248f, 0.7520f, 0),
    float4(0.0263f, 0.0823f, -0.0824f, 0), float4(0.0791f, 0.1915f, -0.1996f, 0), float4(-0.2887f, -0.2888f, -0.1128f, 0), float4(0.3411f, -0.2081f, -0.0800f, 0),
    float4(-0.0056f, -0.2862f, -0.5712f, 0), float4(0.2520f, -0.2032f, 0.2443f, 0), float4(-0.1210f, -0.1726f, 0.1048f, 0), float4(0.0117f, 0.0715f, -0.3834f, 0),
    float4(-0.1312f, -0.2175f, -0.3447f, 0), float4(-0.1238f, 0.1704f, 0.1528f, 0), float4(0.2828f, 0.0530f, 0.2771f, 0), float4(0.0254f, 0.2026f, -0.0941f, 0),
    float4(-0.0285f, -0.1429f, 0.7596f, 0), float4(-0.1314f, -0.0488f, 0.2214f, 0), float4(-0.2869f, -0.2608f, 0.5929f, 0), float4(-0.0995f, 0.0555f, 0.0804f, 0),
    float4(-0.2083f, 0.1569f, -0.0591f, 0), float4(-0.2041f, 0.0711f, 0.5065f, 0), float4(0.0541f, 0.2065f, 0.3323f, 0), float4(0.0945f, -0.1115f, -0.0832f, 0),
    float4(-0.2244f, 0.1592f, -0.1995f, 0), float4(0.3204f, -0.1905f, -0.2473f, 0), float4(0.1155f, -0.2984f, 0.1210f, 0), float4(0.0687f, 0.0617f, -0.1852f, 0),
    float4(0.2071f, -0.1530f, 0.4037f, 0), float4(0.2331f, -0.2653f, -0.5642f, 0), float4(-0.0884f, -0.0034f, -0.3924f, 0), float4(0.2200f, -0.1292f, -0.0800f, 0),
    float4(0.0490f, 0.1309f, 0.1886f, 0), float4(-0.3024f, 0.0708f, -0.2952f, 0), float4(0.2348f, -0.1474f, 0.6444f, 0), float4(-0.0772f, 0.1133f, -0.2063f, 0),
    float4(-0.3383f, 0.1590f, 0.1855f, 0), float4(-0.1679f, -0.0747f, -0.0965f, 0), float4(-0.0633f, -0.0336f, 0.2309f, 0), float4(-0.2784f, -0.2531f, -0.3388f, 0),
    float4(0.0746f, 0.1386f, -0.5796f, 0), float4(-0.2187f, -0.1704f, 0.1508f, 0), float4(0.0250f, 0.0253f, -0.0963f, 0), float4(0.2119f, 0.1898f, -0.6413f, 0),
    float4(-0.0741f, -0.2663f, -0.1682f, 0), float4(0.0970f, 0.0812f, 0.1752f, 0), float4(-0.0343f, -0.0116f, 0.0439f, 0), float4(-0.2609f, 0.1425f, 0.2805f, 0),
    float4(0.0193f, -0.1642f, 0.0836f, 0), float4(-0.2730f, -0.1672f, 0.2499f, 0), float4(0.1357f, 0.1975f, 0.7626f, 0), float4(0.1753f, 0.1166f, -0.1453f, 0),
    float4(-0.3012f, 0.0683f, 0.2789f, 0), float4(0.2167f, 0.0612f, 0.1489f, 0), float4(-0.0999f, -0.2009f, -0.1193f, 0), float4(-0.1315f, -0.1067f, -0.0746f, 0),
    float4(0.3443f, -0.0680f, 0.2430f, 0), float4(0.2646f, -0.2667f, 0.1366f, 0), float4(-0.3388f, 0.0338f, -0.3847f, 0), float4(-0.1290f, -0.0932f, 0.0365f, 0),
    float4(0.1010f, -0.0292f, -0.2775f, 0), float4(0.1887f, 0.0181f, -0.0687f, 0), float4(-0.1119f, -0.0867f, -0.1201f, 0), float4(-0.0802f, 0.2092f, 0.2157f, 0),
    float4(-0.2904f, 0.1764f, 0.3147f, 0), float4(-0.0179f, 0.1110f, 0.5236f, 0), float4(-0.0347f, -0.2818f, 0.0270f, 0), float4(-0.2045f, 0.1278f, -0.1647f, 0),
    float4(-0.0378f, 0.1928f, 0.1761f, 0), float4(-0.0936f, -0.2038f, 0.0185f, 0), float4(0.1401f, -0.1878f, -0.0335f, 0), float4(-0.2128f, -0.0184f, -0.2486f, 0),
    float4(0.0579f, 0.0529f, 0.2103f, 0), float4(0.3273f, -0.1517f, -0.3966f, 0), float4(-0.1276f, 0.1634f, -0.2139f, 0), float4(0.0478f, 0.1876f, -0.0438f, 0),
    float4(0.2608f, 0.0360f, 0.2739f, 0), float4(-0.1436f, -0.0389f, -0.0911f, 0), float4(-0.0937f, 0.1002f, -0.6210f, 0), float4(0.1552f, -0.1740f, 0.1630f, 0),
    float4(-0.0870f, -0.1138f, 0.4736f, 0), float4(-0.1162f, 0.0572f, 0.3258f, 0), float4(-0.0550f, -0.0539f, 0.2130f, 0), float4(0.0447f, 0.1480f, -0.0097f, 0),
    float4(0.1977f, -0.0506f, -0.2010f, 0), float4(0.1086f, -0.1238f, 0.2554f, 0), float4(0.0445f, -0.2065f, -0.1036f, 0), float4(0.3448f, -0.1960f, -0.0006f, 0),
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
    float4(0.2947f, -0.0784f, -0.1183f, 0), float4(-0.0962f, 0.1222f, -0.0645f, 0), float4(0.3322f, -0.2062f, 0.4480f, 0), float4(0.0118f, -0.2426f, -0.4354f, 0),
    float4(0.2958f, -0.0935f, 0.4939f, 0), float4(0.1463f, -0.0447f, -0.0112f, 0), float4(-0.0700f, -0.2269f, -0.6973f, 0), float4(-0.0649f, 0.1918f, 0.1483f, 0),
    float4(-0.2360f, 0.1385f, -0.1467f, 0), float4(0.0760f, -0.2254f, 0.1429f, 0), float4(0.3067f, 0.0213f, -0.4715f, 0), float4(0.0091f, -0.2881f, -0.2216f, 0),
    float4(-0.0601f, -0.0906f, -0.1532f, 0), float4(0.3036f, -0.1053f, -0.0924f, 0), float4(-0.1626f, -0.1197f, -0.0416f, 0), float4(-0.0293f, -0.0781f, -0.0760f, 0),
    float4(-0.2138f, -0.2591f, 0.6902f, 0), float4(-0.1168f, -0.1793f, -0.2042f, 0), float4(-0.1322f, 0.1193f, -0.2674f, 0), float4(-0.2879f, 0.1625f, 0.2355f, 0),
    float4(0.0733f, -0.2412f, -0.0433f, 0), float4(-0.2912f, -0.2440f, -0.0515f, 0), float4(0.2254f, -0.0198f, -0.0772f, 0), float4(-0.0194f, 0.1145f, 0.0830f, 0),
    float4(0.0157f, 0.1279f, -0.2959f, 0), float4(0.3273f, -0.2832f, 0.2459f, 0), float4(-0.1344f, 0.0086f, 0.7986f, 0), float4(-0.1281f, 0.0308f, -0.0757f, 0),
    float4(0.2927f, -0.0800f, -0.4844f, 0), float4(-0.0812f, 0.2001f, 0.2056f, 0), float4(0.2145f, 0.1342f, -0.4475f, 0), float4(0.2512f, -0.0062f, 0.3424f, 0),
    float4(-0.1157f, 0.1159f, 0.4525f, 0), float4(-0.2295f, -0.2749f, 0.4519f, 0), float4(0.2333f, 0.0270f, 0.2615f, 0), float4(0.1434f, 0.0228f, 0.0784f, 0),
    float4(-0.0392f, 0.0608f, -0.3721f, 0), float4(0.0799f, -0.2246f, -0.3184f, 0), float4(-0.1694f, 0.0877f, -0.2558f, 0), float4(-0.0373f, 0.0327f, -0.4820f, 0),
    float4(0.0863f, 0.1712f, -0.1893f, 0), float4(-0.2332f, -0.1656f, -0.3475f, 0), float4(-0.0888f, -0.1948f, -0.3023f, 0), float4(0.0361f, -0.1872f, -0.4164f, 0),
    float4(0.0955f, 0.0083f, 0.0837f, 0), float4(-0.1535f, 0.1079f, 0.1747f, 0), float4(0.0089f, 0.1733f, -0.2182f, 0), float4(-0.0363f, 0.1141f, 0.2663f, 0),
    float4(0.1740f, -0.1279f, 0.2235f, 0), float4(-0.2253f, 0.1812f, -0.4023f, 0), float4(-0.1016f, -0.2533f, -0.4095f, 0), float4(0.1417f, 0.1999f, 0.6534f, 0),
    float4(0.0765f, 0.1179f, -0.2834f, 0), float4(0.0281f, -0.0491f, 0.0964f, 0), float4(-0.1906f, -0.1490f, -0.3092f, 0), float4(-0.0391f, -0.3047f, 0.2249f, 0),
    float4(0.1687f, -0.1638f, -0.4538f, 0), float4(0.0609f, -0.2127f, 0.2715f, 0), float4(0.0937f, 0.1238f, -0.1273f, 0), float4(0.0342f, -0.2404f, -0.1905f, 0),
    float4(0.2189f, -0.1447f, -0.0595f, 0), float4(0.2866f, -0.2132f, 0.4355f, 0), float4(-0.1891f, 0.2117f, -0.1624f, 0), float4(-0.3346f, -0.1699f, -0.7964f, 0),
    float4(0.1101f, 0.1583f, -0.0865f, 0), float4(0.1649f, 0.0926f, -0.1318f, 0), float4(-0.1582f, 0.2129f, -0.0211f, 0), float4(-0.0273f, 0.1914f, -0.0934f, 0),
    float4(0.0264f, -0.2268f, -0.3055f, 0), float4(-0.1003f, -0.1204f, -0.2215f, 0), float4(-0.1125f, 0.1435f, 0.4578f, 0), float4(0.1807f, -0.0244f, 0.0573f, 0),
    float4(-0.0173f, 0.1901f, -0.0661f, 0), float4(0.1722f, -0.0708f, 0.2858f, 0), float4(0.1557f, -0.1323f, -0.6847f, 0), float4(0.1377f, -0.1909f, 0.3506f, 0),
    float4(-0.2265f, 0.1870f, -0.0745f, 0), float4(-0.0583f, -0.0354f, 0.0734f, 0), float4(-0.3126f, -0.0621f, 0.2910f, 0), float4(0.0060f, -0.0115f, 0.5108f, 0),
    float4(-0.0938f, 0.0874f, 0.2185f, 0), float4(0.0683f, -0.1136f, 0.0811f, 0), float4(-0.0657f, -0.1250f, 0.0160f, 0), float4(-0.1506f, 0.0166f, -0.0833f, 0),
    float4(0.2299f, 0.1196f, -0.1257f, 0), float4(0.1128f, 0.0947f, 0.0811f, 0), float4(-0.0550f, -0.2814f, -0.4204f, 0), float4(0.1878f, -0.1307f, 0.2476f, 0),
    float4(0.0492f, 0.0331f, 0.0053f, 0), float4(-0.1049f, 0.0754f, 0.0704f, 0), float4(-0.0179f, -0.2511f, -0.5685f, 0), float4(0.0209f, -0.0317f, -0.0104f, 0),
    float4(-0.1161f, 0.1662f, -0.1836f, 0), float4(-0.2243f, 0.2140f, 0.6126f, 0), float4(-0.0712f, -0.0362f, -0.2636f, 0), float4(-0.1168f, -0.1683f, -0.0230f, 0),
    float4(-0.0304f, 0.0512f, 0.0787f, 0), float4(0.2882f, -0.2166f, 0.1956f, 0), float4(-0.1423f, -0.1441f, 0.1177f, 0), float4(-0.1362f, -0.0676f, 0.1339f, 0),
    float4(0.0555f, 0.0481f, 0.2314f, 0), float4(0.1900f, 0.0589f, -0.0472f, 0), float4(0.1450f, -0.0885f, -0.0083f, 0), float4(-0.3578f, -0.1569f, 0.4160f, 0),
    float4(-0.0754f, 0.1374f, -0.1214f, 0), float4(0.0614f, -0.1509f, -0.2710f, 0), float4(-0.3416f, -0.2051f, 0.2301f, 0), float4(0.0441f, 0.0515f, 0.2869f, 0),
    float4(-0.0724f, 0.1425f, -0.1936f, 0), float4(-0.1850f, 0.1717f, -0.1912f, 0), float4(-0.0196f, -0.0636f, -0.3303f, 0), float4(0.0483f, 0.1233f, -0.0011f, 0),
    float4(0.0717f, -0.0693f, -0.0987f, 0), float4(-0.0186f, -0.1939f, -0.1060f, 0), float4(-0.3491f, -0.2054f, 0.7428f, 0), float4(-0.1012f, 0.0934f, -0.1437f, 0),
    float4(0.0238f, -0.2342f, -0.3754f, 0), float4(-0.1006f, 0.0775f, 0.0554f, 0), float4(-0.1939f, 0.1680f, 0.2175f, 0), float4(0.0245f, 0.0967f, -0.4132f, 0),
    float4(0.0161f, 0.1607f, -0.0753f, 0), float4(-0.3145f, 0.0386f, 0.0256f, 0), float4(-0.3115f, -0.1957f, -0.1022f, 0), float4(-0.0506f, -0.2846f, -0.6136f, 0),
    float4(-0.1206f, -0.3047f, -0.1527f, 0), float4(-0.1770f, -0.1518f, 0.2580f, 0), float4(0.0617f, -0.1138f, 0.1918f, 0), float4(0.3198f, -0.1142f, -0.0433f, 0),
    float4(0.1829f, 0.0247f, -0.7800f, 0), float4(0.0389f, 0.1135f, 0.7151f, 0), float4(-0.1713f, -0.2891f, 0.0613f, 0), float4(-0.2277f, -0.0494f, 0.1265f, 0),
    float4(0.1112f, -0.1377f, 0.0545f, 0), float4(0.0184f, -0.1583f, -0.2421f, 0), float4(0.1724f, 0.0229f, -0.1256f, 0), float4(-0.1279f, -0.2654f, -0.0282f, 0),
    float4(0.0175f, -0.2562f, 0.0789f, 0), float4(-0.0159f, -0.2238f, -0.1483f, 0), float4(-0.0899f, 0.1005f, 0.0890f, 0), float4(0.0694f, -0.0675f, 0.6524f, 0),
    float4(-0.1994f, 0.0865f, -0.0378f, 0), float4(0.3125f, 0.0752f, -0.3787f, 0), float4(0.0237f, -0.0585f, -0.1768f, 0), float4(-0.1055f, -0.1526f, -0.0286f, 0),
    float4(-0.3401f, 0.1498f, -0.2110f, 0), float4(-0.3699f, -0.1859f, 0.5868f, 0), float4(0.3064f, -0.0415f, 0.2421f, 0), float4(0.0374f, 0.1189f, 0.0088f, 0),
    float4(-0.0432f, -0.2221f, -0.0365f, 0), float4(0.0054f, -0.1075f, -0.0330f, 0), float4(-0.1467f, -0.1268f, 0.0073f, 0), float4(0.0194f, -0.1953f, 0.1026f, 0),
    float4(-0.0411f, -0.0241f, -0.2629f, 0), float4(-0.0397f, -0.2486f, 0.4739f, 0), float4(-0.1599f, -0.0674f, 0.1497f, 0), float4(0.0332f, 0.0585f, -0.0145f, 0),
    float4(-0.2279f, -0.1100f, -0.2369f, 0), float4(0.2896f, -0.1901f, 0.3984f, 0), float4(-0.2674f, 0.0234f, 0.2396f, 0), float4(0.0201f, -0.1772f, 0.0687f, 0),
    float4(0.2032f, -0.1243f, -0.2145f, 0), float4(0.1913f, -0.0769f, 0.1747f, 0), float4(0.2961f, -0.0244f, -0.0150f, 0), float4(0.2028f, 0.1911f, 0.2004f, 0),
    float4(-0.3595f, -0.1363f, -0.0237f, 0), float4(0.0246f, -0.2747f, -0.1586f, 0), float4(-0.0553f, -0.0222f, 0.0141f, 0), float4(-0.0296f, 0.0972f, -0.2032f, 0),
    float4(0.0929f, 0.1556f, -0.2503f, 0), float4(-0.1835f, 0.1746f, -0.2609f, 0), float4(-0.2923f, -0.2826f, -0.1834f, 0), float4(-0.1679f, 0.0073f, -0.4709f, 0),
    float4(0.0016f, -0.2767f, -0.1386f, 0), float4(0.3376f, 0.1167f, -0.0235f, 0), float4(0.1836f, -0.1700f, -0.0381f, 0), float4(0.0047f, 0.0340f, -0.0277f, 0),
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
    float4(0.3289f, 0.1678f, 0.0046f, 0), float4(-0.1679f, 0.1375f, -0.0026f, 0), float4(-0.0294f, -0.2120f, -0.2619f, 0), float4(0.1830f, -0.1327f, 0.0927f, 0),
    float4(-0.1378f, -0.0287f, 0.6500f, 0), float4(-0.0089f, -0.0778f, 0.4649f, 0), float4(-0.2422f, 0.2050f, -0.0539f, 0), float4(0.2662f, -0.0868f, 0.1311f, 0),
    float4(0.3082f, -0.0022f, 0.0396f, 0), float4(0.0216f, -0.0476f, 0.2879f, 0), float4(-0.1285f, -0.1660f, -0.0748f, 0), float4(0.0538f, 0.0134f, 0.0038f, 0),
    float4(-0.0768f, -0.2804f, 0.1046f, 0), float4(0.0131f, -0.2757f, 0.1331f, 0), float4(-0.0114f, -0.2723f, 0.6925f, 0), float4(-0.1401f, 0.1219f, 0.2984f, 0),
    float4(-0.0502f, -0.1711f, -0.0191f, 0), float4(0.2805f, 0.1013f, 0.4335f, 0), float4(0.0633f, 0.0813f, -0.0646f, 0), float4(0.0182f, -0.1092f, -0.7900f, 0),
    float4(-0.1049f, 0.1294f, -0.1247f, 0), float4(-0.2957f, -0.2062f, -0.0814f, 0), float4(0.1065f, 0.1306f, 0.4105f, 0), float4(0.3256f, 0.1171f, -0.1798f, 0),
    float4(0.0785f, -0.1158f, -0.3787f, 0), float4(0.0519f, 0.0080f, -0.0272f, 0), float4(0.1215f, -0.1254f, -0.1105f, 0), float4(-0.3162f, 0.1025f, 0.3317f, 0),
    float4(0.0469f, -0.0908f, -0.1052f, 0), float4(-0.1544f, -0.1929f, 0.0996f, 0), float4(0.2060f, 0.2105f, 0.2858f, 0), float4(-0.3043f, -0.2504f, -0.1177f, 0),
    float4(-0.2144f, -0.1588f, 0.0512f, 0), float4(-0.2416f, -0.2789f, -0.7151f, 0), float4(-0.1901f, -0.0224f, -0.0532f, 0), float4(-0.2287f, -0.0432f, -0.1398f, 0),
    float4(0.2617f, 0.0489f, -0.3055f, 0), float4(-0.3331f, -0.2946f, 0.1430f, 0), float4(0.1497f, -0.1658f, 0.2358f, 0), float4(0.3034f, 0.0122f, 0.6694f, 0),
    float4(-0.0071f, 0.1429f, 0.0827f, 0), float4(-0.1535f, -0.1713f, -0.0459f, 0), float4(-0.0748f, -0.1297f, -0.6337f, 0), float4(0.0375f, -0.1248f, -0.3785f, 0),
    float4(-0.1029f, 0.1488f, -0.5971f, 0), float4(0.2055f, -0.1496f, -0.0643f, 0), float4(0.0378f, -0.1211f, 0.0901f, 0), float4(-0.0455f, 0.1462f, 0.0673f, 0),
    float4(-0.2315f, 0.0495f, 0.2081f, 0), float4(-0.1433f, -0.0722f, -0.0505f, 0), float4(-0.1362f, -0.1439f, -0.7631f, 0), float4(0.2493f, 0.1510f, -0.2732f, 0),
    float4(-0.2212f, 0.1608f, 0.0690f, 0), float4(-0.0275f, 0.0222f, 0.0123f, 0), float4(-0.0135f, 0.1415f, 0.4650f, 0), float4(0.0643f, 0.0305f, -0.0982f, 0),
    float4(0.2226f, -0.1926f, -0.6085f, 0), float4(-0.2695f, -0.1219f, -0.0947f, 0), float4(0.0550f, 0.0049f, -0.0810f, 0), float4(-0.2679f, 0.0592f, -0.1991f, 0),
    float4(0.2827f, 0.0096f, 0.0641f, 0), float4(-0.2718f, -0.1386f, 0.2965f, 0), float4(-0.3607f, 0.0999f, 0.4734f, 0), float4(0.0359f, -0.0950f, 0.0121f, 0),
    float4(0.0930f, -0.1487f, -0.1603f, 0), float4(-0.2867f, -0.2145f, 0.6708f, 0), float4(-0.0563f, 0.1564f, 0.2927f, 0), float4(-0.0806f, -0.0947f, -0.0475f, 0),
    float4(0.1750f, -0.2856f, -0.0784f, 0), float4(-0.2634f, -0.2837f, -0.6029f, 0), float4(-0.0593f, 0.1675f, 0.1343f, 0), float4(0.0555f, 0.2113f, -0.5665f, 0),
    float4(0.0419f, 0.1424f, -0.1343f, 0), float4(-0.0278f, 0.1323f, -0.2947f, 0), float4(-0.1168f, 0.0193f, 0.4123f, 0), float4(0.0621f, -0.3049f, 0.0348f, 0),
    float4(0.1223f, 0.0155f, 0.0853f, 0), float4(-0.2821f, -0.2047f, -0.1602f, 0), float4(-0.2249f, -0.1316f, 0.3960f, 0), float4(-0.1691f, 0.0541f, -0.0653f, 0),
    float4(0.0716f, 0.1831f, 0.0564f, 0), float4(0.3446f, -0.1774f, -0.1875f, 0),
};
constant float4 STAR_XYZ[N_STARS] = {   // CIE XYZ flux, erg/s/cm2 x CMF, before extinction
    float4(1.8711e-07f, 1.8512e-07f, 3.8349e-07f, 0), float4(2.4666e-08f, 2.4535e-08f, 4.9208e-08f, 0), float4(3.7862e-08f, 3.7527e-08f, 7.6926e-08f, 0), float4(4.5102e-08f, 4.4775e-08f, 9.0891e-08f, 0),
    float4(3.3734e-08f, 3.3531e-08f, 6.7541e-08f, 0), float4(1.2340e-08f, 1.2303e-08f, 2.4303e-08f, 0), float4(8.8127e-10f, 9.0502e-10f, 1.3530e-09f, 0), float4(3.2721e-09f, 3.2654e-09f, 6.4119e-09f, 0),
    float4(1.8857e-09f, 1.9248e-09f, 3.1247e-09f, 0), float4(4.9343e-10f, 5.0719e-10f, 7.4643e-10f, 0), float4(1.3697e-09f, 1.4115e-09f, 1.9671e-09f, 0), float4(1.5435e-10f, 1.5748e-10f, 1.3574e-10f, 0),
    float4(8.1025e-13f, 7.5831e-13f, 3.1273e-13f, 0), float4(7.8249e-13f, 7.3184e-13f, 3.0044e-13f, 0), float4(8.3124e-13f, 7.7834e-13f, 3.2207e-13f, 0), float4(1.7674e-10f, 1.8230e-10f, 1.9426e-10f, 0),
    float4(3.7941e-12f, 3.6660e-12f, 1.8961e-12f, 0), float4(3.0303e-13f, 2.7890e-13f, 1.0286e-13f, 0), float4(1.5812e-12f, 1.5005e-12f, 6.8078e-13f, 0), float4(7.4238e-13f, 6.9363e-13f, 2.8283e-13f, 0),
    float4(2.6883e-13f, 2.4667e-13f, 8.9192e-14f, 0), float4(9.5768e-12f, 9.4118e-12f, 5.5582e-12f, 0), float4(2.5271e-11f, 2.5282e-11f, 1.7473e-11f, 0), float4(1.3462e-12f, 1.2731e-12f, 5.6367e-13f, 0),
    float4(9.1869e-12f, 9.0221e-12f, 5.2967e-12f, 0), float4(2.7937e-12f, 2.6853e-12f, 1.3362e-12f, 0), float4(2.9101e-13f, 2.6767e-13f, 9.8340e-14f, 0), float4(4.9935e-12f, 4.8490e-12f, 2.6042e-12f, 0),
    float4(1.7868e-12f, 1.7002e-12f, 7.8634e-13f, 0), float4(2.7034e-13f, 2.4811e-13f, 8.9831e-14f, 0), float4(4.4423e-13f, 4.1130e-13f, 1.5779e-13f, 0), float4(9.6673e-13f, 9.0791e-13f, 3.8339e-13f, 0),
    float4(3.9489e-12f, 3.8183e-12f, 1.9854e-12f, 0), float4(9.6314e-13f, 9.0447e-13f, 3.8174e-13f, 0), float4(3.1035e-13f, 2.8574e-13f, 1.0563e-13f, 0), float4(6.6427e-12f, 6.4856e-12f, 3.6333e-12f, 0),
    float4(1.0355e-11f, 1.0191e-11f, 6.0866e-12f, 0), float4(5.8814e-13f, 5.4717e-13f, 2.1678e-13f, 0), float4(1.5666e-10f, 1.6129e-10f, 1.6305e-10f, 0), float4(5.7354e-13f, 5.3335e-13f, 2.1067e-13f, 0),
    float4(5.1079e-12f, 4.9622e-12f, 2.6737e-12f, 0), float4(5.4317e-13f, 5.0462e-13f, 1.9805e-13f, 0), float4(2.3517e-12f, 2.2518e-12f, 1.0894e-12f, 0), float4(2.2179e-11f, 2.2134e-11f, 1.4944e-11f, 0),
    float4(5.1705e-12f, 5.0242e-12f, 2.7118e-12f, 0), float4(2.0452e-12f, 1.9521e-12f, 9.2271e-13f, 0), float4(3.0854e-13f, 2.8404e-13f, 1.0494e-13f, 0), float4(3.6155e-12f, 3.4905e-12f, 1.7939e-12f, 0),
    float4(7.5154e-12f, 7.3553e-12f, 4.2005e-12f, 0), float4(1.0715e-12f, 1.0084e-12f, 4.3197e-13f, 0), float4(3.4035e-13f, 3.1379e-13f, 1.1706e-13f, 0), float4(4.6925e-12f, 4.5515e-12f, 2.4231e-12f, 0),
    float4(4.6653e-13f, 4.3230e-13f, 1.6675e-13f, 0), float4(1.3994e-12f, 1.3244e-12f, 5.8983e-13f, 0), float4(7.2082e-12f, 7.0489e-12f, 3.9992e-12f, 0), float4(2.5407e-13f, 2.3265e-13f, 8.3023e-14f, 0),
    float4(1.4697e-11f, 1.4555e-11f, 9.1707e-12f, 0), float4(6.8396e-12f, 6.6816e-12f, 3.7600e-12f, 0), float4(4.1292e-13f, 3.8185e-13f, 1.4534e-13f, 0), float4(4.4864e-13f, 4.1545e-13f, 1.5956e-13f, 0),
    float4(7.2321e-11f, 7.3422e-11f, 5.9332e-11f, 0), float4(1.5651e-13f, 1.4089e-13f, 4.5032e-14f, 0), float4(3.8165e-13f, 3.5249e-13f, 1.3305e-13f, 0), float4(7.7110e-13f, 7.2098e-13f, 2.9542e-13f, 0),
    float4(1.0712e-12f, 1.0081e-12f, 4.3181e-13f, 0), float4(5.2399e-13f, 4.8650e-13f, 1.9014e-13f, 0), float4(8.0131e-12f, 7.8509e-12f, 4.5226e-12f, 0), float4(5.0370e-12f, 4.8921e-12f, 2.6306e-12f, 0),
    float4(2.4621e-13f, 2.2521e-13f, 7.9782e-14f, 0), float4(3.0737e-11f, 3.0859e-11f, 2.2079e-11f, 0), float4(2.4082e-13f, 2.2010e-13f, 7.7575e-14f, 0), float4(2.3849e-11f, 2.3834e-11f, 1.6301e-11f, 0),
    float4(1.7605e-12f, 1.6746e-12f, 7.7265e-13f, 0), float4(8.5666e-11f, 8.7163e-11f, 7.2432e-11f, 0), float4(5.1203e-12f, 4.9744e-12f, 2.6812e-12f, 0), float4(3.5087e-12f, 3.3857e-12f, 1.7333e-12f, 0),
    float4(3.8375e-12f, 3.7088e-12f, 1.9211e-12f, 0), float4(2.3770e-12f, 2.2766e-12f, 1.1034e-12f, 0), float4(7.7285e-12f, 7.5675e-12f, 4.3381e-12f, 0), float4(2.7721e-11f, 2.7782e-11f, 1.9529e-11f, 0),
    float4(1.9498e-12f, 1.8589e-12f, 8.7186e-13f, 0), float4(1.7130e-13f, 1.5469e-13f, 5.0448e-14f, 0), float4(8.0711e-13f, 7.5532e-13f, 3.1133e-13f, 0), float4(3.6892e-11f, 3.7125e-11f, 2.7189e-11f, 0),
    float4(1.9379e-12f, 1.8473e-12f, 8.6557e-13f, 0), float4(3.8894e-13f, 3.5933e-13f, 1.3590e-13f, 0), float4(3.8308e-13f, 3.5383e-13f, 1.3361e-13f, 0), float4(5.1222e-12f, 4.9764e-12f, 2.6824e-12f, 0),
    float4(2.3150e-13f, 2.1129e-13f, 7.3793e-14f, 0), float4(1.5371e-13f, 1.3828e-13f, 4.4022e-14f, 0), float4(1.3154e-12f, 1.2433e-12f, 5.4860e-13f, 0), float4(1.3241e-12f, 1.2516e-12f, 5.5281e-13f, 0),
    float4(5.9702e-12f, 5.8170e-12f, 3.2066e-12f, 0), float4(3.0137e-12f, 2.9005e-12f, 1.4567e-12f, 0), float4(9.6410e-13f, 9.0539e-13f, 3.8218e-13f, 0), float4(3.8457e-12f, 3.7168e-12f, 1.9258e-12f, 0),
    float4(3.5851e-12f, 3.4607e-12f, 1.7767e-12f, 0), float4(8.6562e-13f, 8.1117e-13f, 3.3746e-13f, 0), float4(4.3195e-13f, 3.9975e-13f, 1.5289e-13f, 0), float4(2.5991e-12f, 2.4945e-12f, 1.2275e-12f, 0),
    float4(2.0319e-13f, 1.8460e-13f, 6.2570e-14f, 0), float4(3.0544e-12f, 2.9404e-12f, 1.4791e-12f, 0), float4(5.5333e-13f, 5.1423e-13f, 2.0226e-13f, 0), float4(2.4034e-12f, 2.3025e-12f, 1.1180e-12f, 0),
    float4(3.1021e-11f, 3.1149e-11f, 2.2312e-11f, 0), float4(2.6586e-13f, 2.4385e-13f, 8.7943e-14f, 0), float4(1.5868e-13f, 1.4291e-13f, 4.5817e-14f, 0), float4(5.3517e-12f, 5.2035e-12f, 2.8226e-12f, 0),
    float4(3.3691e-12f, 3.2487e-12f, 1.6545e-12f, 0), float4(4.9005e-11f, 4.9496e-11f, 3.7695e-11f, 0), float4(3.4592e-12f, 3.3371e-12f, 1.7053e-12f, 0), float4(1.0789e-12f, 1.0155e-12f, 4.3543e-13f, 0),
    float4(1.6354e-11f, 1.6228e-11f, 1.0404e-11f, 0), float4(2.1356e-11f, 2.1297e-11f, 1.4284e-11f, 0), float4(7.0101e-12f, 6.8514e-12f, 3.8703e-12f, 0), float4(1.4799e-11f, 1.4658e-11f, 9.2464e-12f, 0),
    float4(5.8151e-12f, 5.6630e-12f, 3.1095e-12f, 0), float4(2.8292e-12f, 2.7201e-12f, 1.3555e-12f, 0), float4(2.3095e-11f, 2.3066e-11f, 1.5686e-11f, 0), float4(6.0511e-13f, 5.6324e-13f, 2.2391e-13f, 0),
    float4(7.8471e-12f, 7.6857e-12f, 4.4149e-12f, 0), float4(6.6506e-12f, 6.4934e-12f, 3.6383e-12f, 0), float4(6.8075e-12f, 6.6497e-12f, 3.7393e-12f, 0), float4(1.7106e-11f, 1.6988e-11f, 1.0972e-11f, 0),
    float4(9.1457e-13f, 8.5797e-13f, 3.5957e-13f, 0), float4(9.6704e-12f, 9.5054e-12f, 5.6213e-12f, 0), float4(1.8544e-11f, 1.8445e-11f, 1.2075e-11f, 0), float4(4.0858e-13f, 3.7777e-13f, 1.4362e-13f, 0),
    float4(3.7147e-13f, 3.4294e-13f, 1.2908e-13f, 0), float4(1.7565e-13f, 1.5876e-13f, 5.2070e-14f, 0), float4(3.0569e-12f, 2.9427e-12f, 1.4805e-12f, 0), float4(1.1499e-12f, 1.0837e-12f, 4.6891e-13f, 0),
    float4(7.6199e-12f, 7.4595e-12f, 4.2680e-12f, 0), float4(3.1113e-13f, 2.8646e-13f, 1.0592e-13f, 0), float4(2.1223e-11f, 2.1163e-11f, 1.4179e-11f, 0), float4(2.3975e-11f, 2.3962e-11f, 1.6404e-11f, 0),
    float4(3.3942e-13f, 3.1292e-13f, 1.1671e-13f, 0), float4(4.2503e-13f, 3.9323e-13f, 1.5014e-13f, 0), float4(8.5774e-12f, 8.4136e-12f, 4.8922e-12f, 0), float4(2.1224e-11f, 2.1164e-11f, 1.4179e-11f, 0),
    float4(3.0947e-12f, 2.9798e-12f, 1.5014e-12f, 0), float4(3.5485e-13f, 3.2737e-13f, 1.2264e-13f, 0), float4(3.9290e-12f, 3.7988e-12f, 1.9739e-12f, 0), float4(1.2371e-11f, 1.2213e-11f, 7.4909e-12f, 0),
    float4(1.3243e-12f, 1.2519e-12f, 5.5293e-13f, 0), float4(1.7649e-12f, 1.6789e-12f, 7.7497e-13f, 0), float4(1.6499e-13f, 1.4880e-13f, 4.8122e-14f, 0), float4(3.7720e-12f, 3.6443e-12f, 1.8834e-12f, 0),
    float4(5.2808e-12f, 5.1334e-12f, 2.7792e-12f, 0), float4(4.3486e-12f, 4.2121e-12f, 2.2189e-12f, 0), float4(3.6412e-11f, 3.6635e-11f, 2.6784e-11f, 0), float4(2.3726e-12f, 2.2723e-12f, 1.1009e-12f, 0),
    float4(6.7219e-13f, 6.2688e-13f, 2.5243e-13f, 0), float4(1.6142e-13f, 1.4546e-13f, 4.6814e-14f, 0), float4(8.1817e-13f, 7.6586e-13f, 3.1624e-13f, 0), float4(2.9394e-13f, 2.7041e-13f, 9.9442e-14f, 0),
    float4(1.4355e-11f, 1.4210e-11f, 8.9200e-12f, 0), float4(5.7268e-12f, 5.5754e-12f, 3.0545e-12f, 0), float4(1.8751e-12f, 1.7861e-12f, 8.3246e-13f, 0), float4(4.0849e-12f, 3.9522e-12f, 2.0644e-12f, 0),
    float4(1.3726e-12f, 1.2985e-12f, 5.7662e-13f, 0), float4(1.6831e-13f, 1.5190e-13f, 4.9344e-14f, 0), float4(6.1220e-13f, 5.6996e-13f, 2.2690e-13f, 0), float4(2.3477e-11f, 2.3454e-11f, 1.5996e-11f, 0),
    float4(8.1219e-12f, 7.9594e-12f, 4.5935e-12f, 0), float4(1.3372e-11f, 1.3220e-11f, 8.2065e-12f, 0), float4(2.9121e-13f, 2.6786e-13f, 9.8415e-14f, 0), float4(1.1127e-12f, 1.0480e-12f, 4.5133e-13f, 0),
    float4(2.6964e-12f, 2.5902e-12f, 1.2827e-12f, 0), float4(2.2759e-13f, 2.0760e-13f, 7.2218e-14f, 0), float4(5.1249e-12f, 4.9790e-12f, 2.6840e-12f, 0), float4(3.2700e-13f, 3.0130e-13f, 1.1195e-13f, 0),
    float4(2.8933e-12f, 2.7828e-12f, 1.3906e-12f, 0), float4(4.2697e-11f, 4.3047e-11f, 3.2153e-11f, 0), float4(1.4946e-13f, 1.3433e-13f, 4.2498e-14f, 0), float4(2.4342e-13f, 2.2257e-13f, 7.8638e-14f, 0),
    float4(5.9424e-13f, 5.5295e-13f, 2.1934e-13f, 0), float4(2.5772e-13f, 2.3612e-13f, 8.4541e-14f, 0), float4(3.1602e-12f, 3.0440e-12f, 1.5378e-12f, 0), float4(4.7210e-13f, 4.3754e-13f, 1.6899e-13f, 0),
    float4(1.6849e-11f, 1.6728e-11f, 1.0777e-11f, 0), float4(2.8318e-13f, 2.6032e-13f, 9.5282e-14f, 0), float4(2.3862e-13f, 2.1802e-13f, 7.6676e-14f, 0), float4(1.9505e-13f, 1.7695e-13f, 5.9423e-14f, 0),
    float4(3.3327e-13f, 3.0716e-13f, 1.1435e-13f, 0), float4(2.7221e-12f, 2.6154e-12f, 1.2973e-12f, 0), float4(7.0467e-13f, 6.5775e-13f, 2.6643e-13f, 0), float4(2.1113e-12f, 2.0165e-12f, 9.5818e-13f, 0),
    float4(6.1515e-12f, 5.9971e-12f, 3.3207e-12f, 0), float4(5.9248e-13f, 5.5128e-13f, 2.1860e-13f, 0), float4(3.3781e-12f, 3.2575e-12f, 1.6596e-12f, 0), float4(1.3983e-12f, 1.3234e-12f, 5.8928e-13f, 0),
    float4(6.9819e-12f, 6.8234e-12f, 3.8520e-12f, 0), float4(2.1689e-12f, 2.0729e-12f, 9.8936e-13f, 0), float4(2.7384e-13f, 2.5143e-13f, 9.1309e-14f, 0), float4(1.6583e-11f, 1.6460e-11f, 1.0576e-11f, 0),
    float4(6.8710e-11f, 6.9708e-11f, 5.5872e-11f, 0), float4(2.4294e-13f, 2.2211e-13f, 7.8441e-14f, 0), float4(5.1001e-11f, 5.1539e-11f, 3.9478e-11f, 0), float4(7.3056e-12f, 7.1460e-12f, 4.0628e-12f, 0),
    float4(1.8863e-13f, 1.7092e-13f, 5.6966e-14f, 0), float4(6.8633e-12f, 6.7052e-12f, 3.7753e-12f, 0), float4(6.3560e-13f, 5.9215e-13f, 2.3681e-13f, 0), float4(1.4067e-12f, 1.3315e-12f, 5.9343e-13f, 0),
    float4(3.2854e-13f, 3.0274e-13f, 1.1254e-13f, 0), float4(3.0366e-13f, 2.7948e-13f, 1.0310e-13f, 0), float4(7.8937e-13f, 7.3840e-13f, 3.0348e-13f, 0), float4(3.3114e-12f, 3.1921e-12f, 1.6221e-12f, 0),
    float4(9.1775e-13f, 8.6101e-13f, 3.6102e-13f, 0), float4(1.6369e-12f, 1.5545e-12f, 7.0911e-13f, 0), float4(5.1896e-13f, 4.8175e-13f, 1.8808e-13f, 0), float4(1.7712e-13f, 1.6013e-13f, 5.2616e-14f, 0),
    float4(5.0099e-13f, 4.6479e-13f, 1.8072e-13f, 0), float4(1.9829e-12f, 1.8912e-12f, 8.8945e-13f, 0), float4(8.8487e-13f, 8.2957e-13f, 3.4613e-13f, 0), float4(1.4428e-10f, 1.4832e-10f, 1.4481e-10f, 0),
    float4(3.1373e-13f, 2.8889e-13f, 1.0691e-13f, 0), float4(3.1066e-13f, 2.8602e-13f, 1.0574e-13f, 0), float4(7.5114e-13f, 7.0197e-13f, 2.8666e-13f, 0), float4(6.7474e-13f, 6.2931e-13f, 2.5353e-13f, 0),
    float4(5.8085e-12f, 5.6565e-12f, 3.1054e-12f, 0), float4(2.7598e-11f, 2.7657e-11f, 1.9425e-11f, 0), float4(4.3698e-12f, 4.2330e-12f, 2.2314e-12f, 0), float4(2.5343e-12f, 2.4309e-12f, 1.1911e-12f, 0),
    float4(5.0399e-12f, 4.8949e-12f, 2.6324e-12f, 0), float4(3.3899e-13f, 3.1251e-13f, 1.1654e-13f, 0), float4(1.6569e-12f, 1.5740e-12f, 7.1934e-13f, 0), float4(9.9174e-12f, 9.7524e-12f, 5.7884e-12f, 0),
    float4(4.0705e-13f, 3.7633e-13f, 1.4302e-13f, 0), float4(1.7300e-12f, 1.6450e-12f, 7.5692e-13f, 0), float4(2.2213e-11f, 2.2169e-11f, 1.4972e-11f, 0), float4(1.6346e-11f, 1.6220e-11f, 1.0398e-11f, 0),
    float4(1.5078e-12f, 1.4294e-12f, 6.4380e-13f, 0), float4(1.2435e-11f, 1.2278e-11f, 7.5366e-12f, 0), float4(2.2528e-13f, 2.0541e-13f, 7.1291e-14f, 0), float4(1.2633e-12f, 1.1930e-12f, 5.2329e-13f, 0),
    float4(2.0003e-12f, 1.9082e-12f, 8.9869e-13f, 0), float4(5.1613e-12f, 5.0150e-12f, 2.7062e-12f, 0), float4(5.0239e-13f, 4.6611e-13f, 1.8130e-13f, 0), float4(2.0977e-13f, 1.9079e-13f, 6.5141e-14f, 0),
    float4(4.0772e-12f, 3.9446e-12f, 2.0598e-12f, 0), float4(2.4314e-12f, 2.3299e-12f, 1.1335e-12f, 0), float4(1.5487e-11f, 1.5352e-11f, 9.7551e-12f, 0), float4(4.2433e-12f, 4.1083e-12f, 2.1570e-12f, 0),
    float4(8.8469e-12f, 8.6825e-12f, 5.0704e-12f, 0), float4(1.3180e-12f, 1.2458e-12f, 5.4984e-13f, 0), float4(4.3706e-13f, 4.0455e-13f, 1.5493e-13f, 0), float4(4.2811e-13f, 3.9613e-13f, 1.5136e-13f, 0),
    float4(1.4865e-10f, 1.5290e-10f, 1.5116e-10f, 0), float4(1.1011e-11f, 1.0848e-11f, 6.5378e-12f, 0), float4(3.1498e-13f, 2.9006e-13f, 1.0738e-13f, 0), float4(9.4239e-12f, 9.2589e-12f, 5.4554e-12f, 0),
    float4(1.7305e-12f, 1.6454e-12f, 7.5715e-13f, 0), float4(4.8046e-12f, 4.6623e-12f, 2.4903e-12f, 0), float4(5.0027e-11f, 5.0541e-11f, 3.8605e-11f, 0), float4(1.3783e-12f, 1.3040e-12f, 5.7942e-13f, 0),
    float4(7.1555e-12f, 6.9964e-12f, 3.9648e-12f, 0), float4(2.2665e-13f, 2.0670e-13f, 7.1838e-14f, 0), float4(2.5020e-13f, 2.2899e-13f, 8.1422e-14f, 0), float4(1.8685e-11f, 1.8587e-11f, 1.2183e-11f, 0),
    float4(2.0851e-13f, 1.8960e-13f, 6.4648e-14f, 0), float4(1.4806e-10f, 1.5228e-10f, 1.5030e-10f, 0), float4(1.4915e-13f, 1.3404e-13f, 4.2388e-14f, 0), float4(4.8874e-11f, 4.9362e-11f, 3.7578e-11f, 0),
    float4(8.7252e-13f, 8.1777e-13f, 3.4057e-13f, 0), float4(1.1803e-12f, 1.1130e-12f, 4.8340e-13f, 0), float4(2.5511e-13f, 2.3364e-13f, 8.3455e-14f, 0), float4(4.8327e-13f, 4.4808e-13f, 1.7352e-13f, 0),
    float4(6.0443e-11f, 6.1217e-11f, 4.8096e-11f, 0), float4(1.1622e-12f, 1.0956e-12f, 4.7475e-13f, 0), float4(2.3752e-11f, 2.3735e-11f, 1.6221e-11f, 0), float4(5.0361e-13f, 4.6726e-13f, 1.8179e-13f, 0),
    float4(1.7492e-13f, 1.5807e-13f, 5.1794e-14f, 0), float4(6.2991e-12f, 6.1438e-12f, 3.4141e-12f, 0), float4(4.8948e-12f, 4.7514e-12f, 2.5446e-12f, 0), float4(6.5588e-13f, 6.1140e-13f, 2.4545e-13f, 0),
    float4(1.8060e-13f, 1.6339e-13f, 5.3922e-14f, 0), float4(1.8112e-11f, 1.8006e-11f, 1.1741e-11f, 0), float4(2.0323e-12f, 1.9395e-12f, 9.1581e-13f, 0), float4(1.1812e-12f, 1.1139e-12f, 4.8384e-13f, 0),
    float4(1.9937e-11f, 1.9857e-11f, 1.3160e-11f, 0), float4(5.7104e-13f, 5.3098e-13f, 2.0963e-13f, 0), float4(1.1952e-12f, 1.1274e-12f, 4.9053e-13f, 0), float4(2.0502e-12f, 1.9569e-12f, 9.2535e-13f, 0),
    float4(3.5107e-13f, 3.2383e-13f, 1.2118e-13f, 0), float4(1.5277e-13f, 1.3741e-13f, 4.3685e-14f, 0), float4(2.8843e-13f, 2.6526e-13f, 9.7373e-14f, 0), float4(7.8769e-13f, 7.3680e-13f, 3.0274e-13f, 0),
    float4(3.7563e-13f, 3.4685e-13f, 1.3070e-13f, 0), float4(4.6539e-12f, 4.5134e-12f, 2.4001e-12f, 0), float4(9.3460e-12f, 9.1811e-12f, 5.4032e-12f, 0), float4(8.0486e-13f, 7.5317e-13f, 3.1033e-13f, 0),
    float4(8.5274e-13f, 7.9887e-13f, 3.3168e-13f, 0), float4(2.5737e-12f, 2.4696e-12f, 1.2132e-12f, 0), float4(2.6686e-11f, 2.6725e-11f, 1.8655e-11f, 0), float4(1.6981e-13f, 1.5330e-13f, 4.9897e-14f, 0),
    float4(4.9341e-12f, 4.7902e-12f, 2.5683e-12f, 0), float4(1.8340e-13f, 1.6602e-13f, 5.4979e-14f, 0), float4(1.8889e-12f, 1.7996e-12f, 8.3971e-13f, 0), float4(1.0924e-12f, 1.0285e-12f, 4.4178e-13f, 0),
    float4(3.1388e-13f, 2.8903e-13f, 1.0697e-13f, 0), float4(5.4150e-13f, 5.0305e-13f, 1.9736e-13f, 0), float4(8.6546e-12f, 8.4906e-12f, 4.9432e-12f, 0), float4(8.8152e-13f, 8.2637e-13f, 3.4462e-13f, 0),
    float4(5.8409e-12f, 5.6887e-12f, 3.1257e-12f, 0), float4(1.4260e-11f, 1.4115e-11f, 8.8510e-12f, 0), float4(2.8724e-11f, 2.8807e-11f, 2.0384e-11f, 0), float4(3.5496e-13f, 3.2747e-13f, 1.2269e-13f, 0),
    float4(3.8188e-12f, 3.6903e-12f, 1.9103e-12f, 0), float4(8.7260e-12f, 8.5619e-12f, 4.9904e-12f, 0), float4(9.6615e-13f, 9.0735e-13f, 3.8312e-13f, 0), float4(1.6961e-12f, 1.6120e-12f, 7.3944e-13f, 0),
    float4(7.4022e-13f, 6.9157e-13f, 2.8189e-13f, 0), float4(2.6083e-12f, 2.5036e-12f, 1.2328e-12f, 0), float4(9.8736e-12f, 9.7086e-12f, 5.7586e-12f, 0), float4(4.8106e-11f, 4.8576e-11f, 3.6896e-11f, 0),
    float4(9.5605e-12f, 9.3955e-12f, 5.5472e-12f, 0), float4(2.2995e-12f, 2.2007e-12f, 1.0606e-12f, 0), float4(1.3756e-12f, 1.3014e-12f, 5.7809e-13f, 0), float4(2.3617e-12f, 2.2616e-12f, 1.0949e-12f, 0),
    float4(2.9923e-13f, 2.7535e-13f, 1.0143e-13f, 0), float4(2.4065e-13f, 2.1995e-13f, 7.7506e-14f, 0), float4(8.9774e-13f, 8.4188e-13f, 3.5195e-13f, 0), float4(2.0909e-11f, 2.0844e-11f, 1.3929e-11f, 0),
    float4(3.2614e-13f, 3.0049e-13f, 1.1163e-13f, 0), float4(4.0473e-13f, 3.7415e-13f, 1.4210e-13f, 0), float4(3.3015e-13f, 3.0425e-13f, 1.1316e-13f, 0), float4(3.5803e-12f, 3.4559e-12f, 1.7739e-12f, 0),
    float4(5.0531e-13f, 4.6886e-13f, 1.8249e-13f, 0), float4(1.6892e-13f, 1.5247e-13f, 4.9570e-14f, 0), float4(1.9500e-13f, 1.7690e-13f, 5.9402e-14f, 0), float4(5.2241e-12f, 5.0773e-12f, 2.7446e-12f, 0),
    float4(2.0769e-13f, 1.8883e-13f, 6.4324e-14f, 0), float4(3.3075e-13f, 3.0481e-13f, 1.1339e-13f, 0), float4(3.9262e-12f, 3.7959e-12f, 1.9722e-12f, 0), float4(7.7646e-13f, 7.2609e-13f, 2.9778e-13f, 0),
    float4(5.2259e-12f, 5.0790e-12f, 2.7456e-12f, 0), float4(4.0893e-13f, 3.7810e-13f, 1.4376e-13f, 0), float4(4.2759e-13f, 3.9564e-13f, 1.5115e-13f, 0), float4(5.4299e-11f, 5.4917e-11f, 4.2455e-11f, 0),
    float4(5.6127e-12f, 5.4623e-12f, 2.9837e-12f, 0), float4(2.5880e-13f, 2.3714e-13f, 8.4990e-14f, 0), float4(1.0262e-12f, 9.6489e-13f, 4.1082e-13f, 0), float4(6.9486e-12f, 6.7902e-12f, 3.8305e-12f, 0),
    float4(2.9669e-13f, 2.7298e-13f, 1.0047e-13f, 0), float4(4.1693e-12f, 4.0354e-12f, 2.1136e-12f, 0), float4(3.1744e-13f, 2.9236e-13f, 1.0832e-13f, 0), float4(3.0206e-12f, 2.9072e-12f, 1.4604e-12f, 0),
    float4(1.4658e-13f, 1.3166e-13f, 4.1474e-14f, 0), float4(2.8605e-13f, 2.6305e-13f, 9.6484e-14f, 0), float4(4.5321e-11f, 4.5728e-11f, 3.4441e-11f, 0), float4(5.2488e-13f, 4.8734e-13f, 1.9051e-13f, 0),
    float4(2.5142e-11f, 2.5150e-11f, 1.7366e-11f, 0), float4(8.3883e-13f, 7.8558e-13f, 3.2545e-13f, 0), float4(2.5157e-12f, 2.4126e-12f, 1.1806e-12f, 0), float4(3.3622e-11f, 3.3794e-11f, 2.4454e-11f, 0),
    float4(1.8144e-12f, 1.7270e-12f, 8.0069e-13f, 0), float4(2.0455e-11f, 2.0383e-11f, 1.3569e-11f, 0), float4(2.2165e-11f, 2.2120e-11f, 1.4933e-11f, 0), float4(4.1114e-13f, 3.8018e-13f, 1.4464e-13f, 0),
    float4(2.9672e-13f, 2.7301e-13f, 1.0049e-13f, 0), float4(3.0669e-13f, 2.8232e-13f, 1.0424e-13f, 0), float4(3.3427e-11f, 3.3596e-11f, 2.4292e-11f, 0), float4(2.1167e-12f, 2.0218e-12f, 9.6110e-13f, 0),
    float4(9.6492e-13f, 9.0618e-13f, 3.8256e-13f, 0), float4(1.7835e-12f, 1.6970e-12f, 7.8462e-13f, 0), float4(1.0809e-12f, 1.0174e-12f, 4.3635e-13f, 0), float4(6.6948e-11f, 6.7897e-11f, 5.4197e-11f, 0),
    float4(3.3803e-13f, 3.1161e-13f, 1.1617e-13f, 0), float4(6.9266e-13f, 6.4634e-13f, 2.6125e-13f, 0), float4(1.1009e-11f, 1.0846e-11f, 6.5366e-12f, 0), float4(3.7057e-11f, 3.7292e-11f, 2.7328e-11f, 0),
    float4(7.4783e-13f, 6.9882e-13f, 2.8521e-13f, 0), float4(1.3802e-12f, 1.3059e-12f, 5.8035e-13f, 0), float4(1.6798e-11f, 1.6677e-11f, 1.0739e-11f, 0), float4(3.5110e-13f, 3.2385e-13f, 1.2120e-13f, 0),
    float4(4.8929e-13f, 4.5375e-13f, 1.7596e-13f, 0), float4(5.8740e-12f, 5.7215e-12f, 3.1464e-12f, 0), float4(9.4580e-13f, 8.8787e-13f, 3.7380e-13f, 0), float4(2.2510e-13f, 2.0525e-13f, 7.1220e-14f, 0),
    float4(4.6870e-12f, 4.5460e-12f, 2.4198e-12f, 0), float4(2.7432e-12f, 2.6361e-12f, 1.3088e-12f, 0), float4(7.1294e-13f, 6.6562e-13f, 2.7002e-13f, 0), float4(6.1914e-12f, 6.0368e-12f, 3.3459e-12f, 0),
    float4(7.9076e-12f, 7.7459e-12f, 4.4541e-12f, 0), float4(4.5946e-12f, 4.4548e-12f, 2.3647e-12f, 0), float4(3.9590e-12f, 3.8283e-12f, 1.9912e-12f, 0), float4(2.2589e-12f, 2.1609e-12f, 1.0383e-12f, 0),
    float4(8.6045e-13f, 8.0624e-13f, 3.3514e-13f, 0), float4(1.4612e-12f, 1.3842e-12f, 6.2050e-13f, 0), float4(1.5825e-13f, 1.4251e-13f, 4.5662e-14f, 0), float4(5.9950e-12f, 5.8416e-12f, 3.2221e-12f, 0),
    float4(2.4234e-13f, 2.2155e-13f, 7.8197e-14f, 0), float4(7.9394e-13f, 7.4275e-13f, 3.0550e-13f, 0), float4(3.0271e-13f, 2.7860e-13f, 1.0274e-13f, 0), float4(7.4821e-12f, 7.3221e-12f, 4.1786e-12f, 0),
    float4(2.9225e-11f, 2.9319e-11f, 2.0813e-11f, 0), float4(4.3159e-12f, 4.1798e-12f, 2.1996e-12f, 0), float4(2.1272e-12f, 2.0321e-12f, 9.6676e-13f, 0), float4(2.5651e-12f, 2.4612e-12f, 1.2084e-12f, 0),
    float4(7.9470e-13f, 7.4348e-13f, 3.0584e-13f, 0), float4(1.0200e-11f, 1.0035e-11f, 5.9802e-12f, 0), float4(1.8835e-12f, 1.7943e-12f, 8.3687e-13f, 0), float4(8.4616e-13f, 7.9259e-13f, 3.2873e-13f, 0),
    float4(2.8030e-13f, 2.5758e-13f, 9.4055e-14f, 0), float4(1.5846e-13f, 1.4271e-13f, 4.5740e-14f, 0), float4(1.8411e-13f, 1.6669e-13f, 5.5250e-14f, 0), float4(4.6349e-11f, 4.6779e-11f, 3.5344e-11f, 0),
    float4(1.0519e-10f, 1.0732e-10f, 9.2415e-11f, 0), float4(7.3422e-13f, 6.8586e-13f, 2.7927e-13f, 0), float4(5.5638e-13f, 5.1711e-13f, 2.0353e-13f, 0), float4(1.7459e-12f, 1.6604e-12f, 7.6509e-13f, 0),
    float4(1.0226e-12f, 9.6152e-13f, 4.0920e-13f, 0), float4(6.8337e-13f, 6.3751e-13f, 2.5724e-13f, 0), float4(3.0876e-13f, 2.8424e-13f, 1.0502e-13f, 0), float4(1.3323e-12f, 1.2596e-12f, 5.5685e-13f, 0),
    float4(3.7780e-13f, 3.4888e-13f, 1.3155e-13f, 0), float4(2.9287e-11f, 2.9382e-11f, 2.0866e-11f, 0), float4(6.2672e-12f, 6.1121e-12f, 3.3939e-12f, 0), float4(2.7800e-12f, 2.6720e-12f, 1.3288e-12f, 0),
    float4(1.7320e-12f, 1.6469e-12f, 7.5795e-13f, 0), float4(2.3426e-13f, 2.1390e-13f, 7.4906e-14f, 0), float4(1.8180e-13f, 1.6452e-13f, 5.4377e-14f, 0), float4(1.0956e-12f, 1.0315e-12f, 4.4326e-13f, 0),
    float4(6.3540e-12f, 6.1984e-12f, 3.4490e-12f, 0), float4(2.8397e-13f, 2.6108e-13f, 9.5622e-14f, 0), float4(1.7210e-12f, 1.6362e-12f, 7.5226e-13f, 0), float4(4.0791e-12f, 3.9465e-12f, 2.0609e-12f, 0),
    float4(2.7969e-12f, 2.6885e-12f, 1.3379e-12f, 0), float4(8.8020e-12f, 8.6377e-12f, 5.0406e-12f, 0), float4(1.5513e-13f, 1.3960e-13f, 4.4532e-14f, 0), float4(2.2286e-13f, 2.0313e-13f, 7.0324e-14f, 0),
    float4(3.9236e-12f, 3.7934e-12f, 1.9707e-12f, 0), float4(1.1848e-11f, 1.1688e-11f, 7.1220e-12f, 0), float4(5.3216e-12f, 5.1738e-12f, 2.8042e-12f, 0), float4(1.3279e-12f, 1.2553e-12f, 5.5469e-13f, 0),
    float4(8.0254e-13f, 7.5096e-13f, 3.0931e-13f, 0), float4(4.5822e-13f, 4.2447e-13f, 1.6340e-13f, 0), float4(1.1120e-12f, 1.0474e-12f, 4.5101e-13f, 0), float4(2.2523e-11f, 2.2484e-11f, 1.5222e-11f, 0),
    float4(1.5091e-12f, 1.4306e-12f, 6.4443e-13f, 0), float4(3.1357e-12f, 3.0199e-12f, 1.5241e-12f, 0), float4(9.4319e-13f, 8.8537e-13f, 3.7261e-13f, 0), float4(2.9278e-13f, 2.6932e-13f, 9.9005e-14f, 0),
    float4(1.8075e-11f, 1.7969e-11f, 1.1713e-11f, 0), float4(3.5641e-13f, 3.2882e-13f, 1.2324e-13f, 0), float4(1.0200e-12f, 9.5894e-13f, 4.0795e-13f, 0), float4(9.7296e-13f, 9.1388e-13f, 3.8625e-13f, 0),
    float4(5.6673e-13f, 5.2690e-13f, 2.0783e-13f, 0), float4(6.1376e-11f, 6.2174e-11f, 4.8963e-11f, 0), float4(2.0954e-11f, 2.0889e-11f, 1.3964e-11f, 0), float4(3.0123e-13f, 2.7721e-13f, 1.0218e-13f, 0),
    float4(4.9801e-11f, 5.0310e-11f, 3.8404e-11f, 0), float4(6.8050e-12f, 6.6472e-12f, 3.7377e-12f, 0), float4(8.9027e-13f, 8.3474e-13f, 3.4857e-13f, 0), float4(4.8674e-13f, 4.5135e-13f, 1.7493e-13f, 0),
    float4(2.1466e-13f, 1.9539e-13f, 6.7064e-14f, 0), float4(1.9288e-12f, 1.8384e-12f, 8.6074e-13f, 0), float4(3.8655e-12f, 3.7362e-12f, 1.9372e-12f, 0), float4(1.8068e-13f, 1.6347e-13f, 5.3953e-14f, 0),
    float4(2.2261e-12f, 2.1288e-12f, 1.0204e-12f, 0), float4(4.8984e-13f, 4.5427e-13f, 1.7619e-13f, 0), float4(6.4866e-12f, 6.3303e-12f, 3.5334e-12f, 0), float4(1.0264e-11f, 1.0099e-11f, 6.0243e-12f, 0),
    float4(8.0123e-13f, 7.4971e-13f, 3.0873e-13f, 0), float4(3.7539e-12f, 3.6265e-12f, 1.8730e-12f, 0), float4(1.8779e-12f, 1.7888e-12f, 8.3393e-13f, 0), float4(9.5614e-12f, 9.3964e-12f, 5.5479e-12f, 0),
    float4(2.5352e-12f, 2.4318e-12f, 1.1916e-12f, 0), float4(2.5263e-12f, 2.4231e-12f, 1.1866e-12f, 0), float4(2.6125e-13f, 2.3947e-13f, 8.6014e-14f, 0), float4(4.1463e-13f, 3.8346e-13f, 1.4602e-13f, 0),
    float4(1.1610e-12f, 1.0944e-12f, 4.7418e-13f, 0), float4(1.5329e-12f, 1.4536e-12f, 6.5638e-13f, 0), float4(1.2609e-12f, 1.1907e-12f, 5.2211e-13f, 0), float4(1.5066e-11f, 1.4927e-11f, 9.4429e-12f, 0),
    float4(3.2399e-13f, 2.9848e-13f, 1.1080e-13f, 0), float4(5.2335e-12f, 5.0865e-12f, 2.7502e-12f, 0), float4(6.3773e-13f, 5.9417e-13f, 2.3771e-13f, 0), float4(3.4823e-13f, 3.2117e-13f, 1.2009e-13f, 0),
    float4(3.2515e-13f, 2.9957e-13f, 1.1125e-13f, 0), float4(1.9678e-13f, 1.7857e-13f, 6.0089e-14f, 0), float4(2.7614e-13f, 2.5362e-13f, 9.2283e-14f, 0), float4(5.9254e-13f, 5.5133e-13f, 2.1862e-13f, 0),
    float4(5.4970e-13f, 5.1080e-13f, 2.0075e-13f, 0), float4(1.0732e-12f, 1.0101e-12f, 4.3277e-13f, 0), float4(1.0068e-12f, 9.4631e-13f, 4.0185e-13f, 0), float4(5.7458e-13f, 5.3433e-13f, 2.1111e-13f, 0),
    float4(2.0696e-13f, 1.8814e-13f, 6.4039e-14f, 0), float4(8.4006e-12f, 8.2373e-12f, 4.7760e-12f, 0), float4(2.2533e-13f, 2.0546e-13f, 7.1310e-14f, 0), float4(3.8874e-13f, 3.5914e-13f, 1.3582e-13f, 0),
    float4(3.2387e-12f, 3.1209e-12f, 1.5815e-12f, 0), float4(1.2919e-10f, 1.3249e-10f, 1.2362e-10f, 0), float4(7.6219e-12f, 7.4614e-12f, 4.2693e-12f, 0), float4(6.4382e-12f, 6.2821e-12f, 3.5025e-12f, 0),
    float4(6.7406e-13f, 6.2866e-13f, 2.5324e-13f, 0), float4(3.3028e-12f, 3.1836e-12f, 1.6173e-12f, 0), float4(4.3838e-13f, 4.0579e-13f, 1.5545e-13f, 0), float4(5.5350e-13f, 5.1439e-13f, 2.0233e-13f, 0),
    float4(3.5333e-12f, 3.4098e-12f, 1.7472e-12f, 0), float4(3.9791e-12f, 3.8480e-12f, 2.0028e-12f, 0), float4(2.0602e-11f, 2.0532e-11f, 1.3685e-11f, 0), float4(2.6801e-11f, 2.6843e-11f, 1.8752e-11f, 0),
    float4(1.1724e-12f, 1.1055e-12f, 4.7964e-13f, 0), float4(8.2072e-12f, 8.0444e-12f, 4.6493e-12f, 0), float4(6.0089e-12f, 5.8554e-12f, 3.2309e-12f, 0), float4(2.0492e-12f, 1.9559e-12f, 9.2482e-13f, 0),
    float4(1.5060e-13f, 1.3539e-13f, 4.2904e-14f, 0), float4(1.0834e-12f, 1.0199e-12f, 4.3756e-13f, 0), float4(1.7432e-11f, 1.7318e-11f, 1.1220e-11f, 0), float4(4.1542e-12f, 4.0205e-12f, 2.1048e-12f, 0),
    float4(5.8519e-13f, 5.4438e-13f, 2.1554e-13f, 0), float4(3.1345e-13f, 2.8863e-13f, 1.0680e-13f, 0), float4(8.2676e-13f, 7.7406e-13f, 3.2007e-13f, 0), float4(5.3699e-13f, 4.9878e-13f, 1.9550e-13f, 0),
    float4(1.0676e-12f, 1.0047e-12f, 4.3015e-13f, 0), float4(1.2774e-12f, 1.2066e-12f, 5.3009e-13f, 0), float4(4.1841e-12f, 4.0499e-12f, 2.1223e-12f, 0), float4(2.0205e-11f, 2.0129e-11f, 1.3372e-11f, 0),
    float4(3.0555e-11f, 3.0675e-11f, 2.1931e-11f, 0), float4(2.0661e-13f, 1.8781e-13f, 6.3903e-14f, 0), float4(2.0473e-13f, 1.8604e-13f, 6.3168e-14f, 0), float4(9.0189e-12f, 8.8543e-12f, 5.1847e-12f, 0),
    float4(1.2266e-12f, 1.1576e-12f, 5.0559e-13f, 0), float4(1.6656e-12f, 1.5824e-12f, 7.2378e-13f, 0), float4(2.3481e-11f, 2.3459e-11f, 1.6000e-11f, 0), float4(3.2530e-13f, 2.9971e-13f, 1.1131e-13f, 0),
    float4(1.1029e-11f, 1.0866e-11f, 6.5500e-12f, 0), float4(3.1723e-13f, 2.9216e-13f, 1.0824e-13f, 0), float4(1.4396e-12f, 1.3633e-12f, 6.0974e-13f, 0), float4(4.7174e-11f, 4.7623e-11f, 3.6071e-11f, 0),
    float4(1.6914e-12f, 1.6074e-12f, 7.3701e-13f, 0), float4(6.2027e-12f, 6.0479e-12f, 3.3530e-12f, 0), float4(6.9958e-12f, 6.8372e-12f, 3.8610e-12f, 0), float4(4.3651e-13f, 4.0403e-13f, 1.5471e-13f, 0),
    float4(9.5540e-13f, 8.9705e-13f, 3.7819e-13f, 0), float4(2.2226e-13f, 2.0256e-13f, 7.0084e-14f, 0), float4(1.4601e-12f, 1.3831e-12f, 6.1994e-13f, 0), float4(1.7809e-12f, 1.6944e-12f, 7.8325e-13f, 0),
    float4(7.1253e-12f, 6.9663e-12f, 3.9451e-12f, 0), float4(4.4264e-12f, 4.2888e-12f, 2.2648e-12f, 0), float4(1.5886e-12f, 1.5077e-12f, 6.8455e-13f, 0), float4(8.5048e-12f, 8.3412e-12f, 4.8444e-12f, 0),
    float4(3.8998e-13f, 3.6030e-13f, 1.3631e-13f, 0), float4(4.3983e-13f, 4.0716e-13f, 1.5603e-13f, 0), float4(1.7638e-12f, 1.6778e-12f, 7.7438e-13f, 0), float4(3.3922e-11f, 3.4099e-11f, 2.4703e-11f, 0),
    float4(5.3095e-12f, 5.1618e-12f, 2.7968e-12f, 0), float4(1.8836e-13f, 1.7067e-13f, 5.6862e-14f, 0), float4(6.5693e-12f, 6.4125e-12f, 3.5863e-12f, 0), float4(7.9940e-13f, 7.4796e-13f, 3.0791e-13f, 0),
    float4(6.1048e-13f, 5.6833e-13f, 2.2617e-13f, 0), float4(8.8108e-13f, 8.2595e-13f, 3.4442e-13f, 0), float4(2.6520e-13f, 2.4322e-13f, 8.7665e-14f, 0), float4(9.8964e-12f, 9.7314e-12f, 5.7741e-12f, 0),
    float4(3.1623e-12f, 3.0460e-12f, 1.5389e-12f, 0), float4(5.6104e-13f, 5.2152e-13f, 2.0546e-13f, 0), float4(3.3785e-11f, 3.3960e-11f, 2.4589e-11f, 0), float4(2.2189e-11f, 2.2145e-11f, 1.4953e-11f, 0),
    float4(2.3334e-12f, 2.2339e-12f, 1.0793e-12f, 0), float4(1.7856e-13f, 1.6148e-13f, 5.3156e-14f, 0), float4(6.4189e-13f, 5.9812e-13f, 2.3949e-13f, 0), float4(2.6106e-13f, 2.3929e-13f, 8.5931e-14f, 0),
    float4(4.2731e-13f, 3.9538e-13f, 1.5105e-13f, 0), float4(3.9818e-13f, 3.6800e-13f, 1.3953e-13f, 0), float4(8.5775e-13f, 8.0366e-13f, 3.3393e-13f, 0), float4(5.1861e-13f, 4.8142e-13f, 1.8793e-13f, 0),
    float4(8.6091e-12f, 8.4453e-12f, 4.9132e-12f, 0), float4(1.5566e-13f, 1.4010e-13f, 4.4726e-14f, 0),
};
constant float4 STAR_K[N_STARS] = {   // each star's own A/A_Hb in X, Y, Z (its spectrum through the CMFs)
    float4(0.9241f, 0.9103f, 1.0575f, 0), float4(0.9218f, 0.9097f, 1.0572f, 0), float4(0.9234f, 0.9101f, 1.0574f, 0), float4(0.9227f, 0.9099f, 1.0573f, 0),
    float4(0.9221f, 0.9098f, 1.0572f, 0), float4(0.9208f, 0.9094f, 1.0570f, 0), float4(0.9029f, 0.9041f, 1.0540f, 0), float4(0.9203f, 0.9093f, 1.0569f, 0),
    float4(0.9079f, 0.9056f, 1.0549f, 0), float4(0.9020f, 0.9038f, 1.0538f, 0), float4(0.8989f, 0.9028f, 1.0533f, 0), float4(0.8763f, 0.8942f, 1.0481f, 0),
    float4(0.8548f, 0.8820f, 1.0398f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8548f, 0.8821f, 1.0399f, 0), float4(0.8853f, 0.8979f, 1.0504f, 0),
    float4(0.8601f, 0.8857f, 1.0424f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8569f, 0.8836f, 1.0409f, 0), float4(0.8545f, 0.8818f, 1.0397f, 0),
    float4(0.8521f, 0.8799f, 1.0383f, 0), float4(0.8637f, 0.8879f, 1.0439f, 0), float4(0.8684f, 0.8905f, 1.0456f, 0), float4(0.8563f, 0.8832f, 1.0406f, 0),
    float4(0.8635f, 0.8878f, 1.0438f, 0), float4(0.8591f, 0.8850f, 1.0420f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8611f, 0.8863f, 1.0428f, 0),
    float4(0.8573f, 0.8839f, 1.0411f, 0), float4(0.8521f, 0.8800f, 1.0383f, 0), float4(0.8533f, 0.8809f, 1.0390f, 0), float4(0.8553f, 0.8824f, 1.0401f, 0),
    float4(0.8602f, 0.8858f, 1.0425f, 0), float4(0.8553f, 0.8824f, 1.0401f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8622f, 0.8870f, 1.0433f, 0),
    float4(0.8640f, 0.8880f, 1.0440f, 0), float4(0.8539f, 0.8814f, 1.0394f, 0), float4(0.8829f, 0.8970f, 1.0498f, 0), float4(0.8539f, 0.8813f, 1.0393f, 0),
    float4(0.8611f, 0.8863f, 1.0429f, 0), float4(0.8537f, 0.8812f, 1.0393f, 0), float4(0.8584f, 0.8846f, 1.0417f, 0), float4(0.8677f, 0.8901f, 1.0454f, 0),
    float4(0.8612f, 0.8864f, 1.0429f, 0), float4(0.8578f, 0.8842f, 1.0414f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8599f, 0.8856f, 1.0423f, 0),
    float4(0.8627f, 0.8873f, 1.0435f, 0), float4(0.8556f, 0.8826f, 1.0403f, 0), float4(0.8527f, 0.8804f, 1.0387f, 0), float4(0.8608f, 0.8861f, 1.0427f, 0),
    float4(0.8534f, 0.8810f, 1.0391f, 0), float4(0.8565f, 0.8833f, 1.0407f, 0), float4(0.8625f, 0.8872f, 1.0434f, 0), float4(0.8518f, 0.8797f, 1.0382f, 0),
    float4(0.8656f, 0.8889f, 1.0446f, 0), float4(0.8623f, 0.8871f, 1.0434f, 0), float4(0.8531f, 0.8808f, 1.0389f, 0), float4(0.8533f, 0.8809f, 1.0390f, 0),
    float4(0.8739f, 0.8931f, 1.0474f, 0), float4(0.8498f, 0.8780f, 1.0369f, 0), float4(0.8529f, 0.8806f, 1.0388f, 0), float4(0.8546f, 0.8819f, 1.0398f, 0),
    float4(0.8556f, 0.8826f, 1.0403f, 0), float4(0.8536f, 0.8812f, 1.0392f, 0), float4(0.8630f, 0.8874f, 1.0436f, 0), float4(0.8611f, 0.8863f, 1.0428f, 0),
    float4(0.8517f, 0.8796f, 1.0381f, 0), float4(0.8696f, 0.8911f, 1.0460f, 0), float4(0.8516f, 0.8795f, 1.0380f, 0), float4(0.8681f, 0.8903f, 1.0455f, 0),
    float4(0.8573f, 0.8838f, 1.0411f, 0), float4(0.8749f, 0.8936f, 1.0477f, 0), float4(0.8611f, 0.8863f, 1.0429f, 0), float4(0.8598f, 0.8855f, 1.0423f, 0),
    float4(0.8601f, 0.8857f, 1.0424f, 0), float4(0.8585f, 0.8846f, 1.0417f, 0), float4(0.8628f, 0.8874f, 1.0436f, 0), float4(0.8690f, 0.8908f, 1.0458f, 0),
    float4(0.8577f, 0.8841f, 1.0413f, 0), float4(0.8501f, 0.8783f, 1.0371f, 0), float4(0.8548f, 0.8820f, 1.0398f, 0), float4(0.8704f, 0.8915f, 1.0463f, 0),
    float4(0.8576f, 0.8841f, 1.0413f, 0), float4(0.8530f, 0.8807f, 1.0388f, 0), float4(0.8529f, 0.8806f, 1.0388f, 0), float4(0.8612f, 0.8863f, 1.0429f, 0),
    float4(0.8514f, 0.8794f, 1.0379f, 0), float4(0.8497f, 0.8780f, 1.0369f, 0), float4(0.8563f, 0.8831f, 1.0406f, 0), float4(0.8563f, 0.8831f, 1.0406f, 0),
    float4(0.8617f, 0.8867f, 1.0431f, 0), float4(0.8593f, 0.8852f, 1.0421f, 0), float4(0.8553f, 0.8824f, 1.0401f, 0), float4(0.8601f, 0.8857f, 1.0424f, 0),
    float4(0.8599f, 0.8856f, 1.0423f, 0), float4(0.8549f, 0.8822f, 1.0399f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0), float4(0.8588f, 0.8849f, 1.0418f, 0),
    float4(0.8508f, 0.8789f, 1.0376f, 0), float4(0.8594f, 0.8852f, 1.0421f, 0), float4(0.8538f, 0.8813f, 1.0393f, 0), float4(0.8585f, 0.8846f, 1.0417f, 0),
    float4(0.8696f, 0.8911f, 1.0460f, 0), float4(0.8520f, 0.8799f, 1.0383f, 0), float4(0.8498f, 0.8781f, 1.0369f, 0), float4(0.8613f, 0.8865f, 1.0429f, 0),
    float4(0.8597f, 0.8854f, 1.0422f, 0), float4(0.8717f, 0.8921f, 1.0467f, 0), float4(0.8598f, 0.8855f, 1.0423f, 0), float4(0.8556f, 0.8826f, 1.0403f, 0),
    float4(0.8661f, 0.8892f, 1.0448f, 0), float4(0.8675f, 0.8900f, 1.0453f, 0), float4(0.8624f, 0.8871f, 1.0434f, 0), float4(0.8656f, 0.8889f, 1.0446f, 0),
    float4(0.8616f, 0.8867f, 1.0431f, 0), float4(0.8591f, 0.8851f, 1.0420f, 0), float4(0.8679f, 0.8902f, 1.0455f, 0), float4(0.8540f, 0.8814f, 1.0394f, 0),
    float4(0.8629f, 0.8874f, 1.0436f, 0), float4(0.8622f, 0.8870f, 1.0433f, 0), float4(0.8623f, 0.8870f, 1.0433f, 0), float4(0.8663f, 0.8893f, 1.0449f, 0),
    float4(0.8551f, 0.8823f, 1.0400f, 0), float4(0.8637f, 0.8879f, 1.0439f, 0), float4(0.8667f, 0.8896f, 1.0450f, 0), float4(0.8531f, 0.8807f, 1.0389f, 0),
    float4(0.8529f, 0.8806f, 1.0388f, 0), float4(0.8502f, 0.8784f, 1.0372f, 0), float4(0.8594f, 0.8852f, 1.0421f, 0), float4(0.8558f, 0.8828f, 1.0404f, 0),
    float4(0.8628f, 0.8873f, 1.0435f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8674f, 0.8900f, 1.0453f, 0), float4(0.8681f, 0.8903f, 1.0455f, 0),
    float4(0.8527f, 0.8804f, 1.0387f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0), float4(0.8632f, 0.8876f, 1.0437f, 0), float4(0.8674f, 0.8900f, 1.0453f, 0),
    float4(0.8594f, 0.8852f, 1.0421f, 0), float4(0.8528f, 0.8805f, 1.0387f, 0), float4(0.8602f, 0.8857f, 1.0425f, 0), float4(0.8648f, 0.8885f, 1.0443f, 0),
    float4(0.8563f, 0.8831f, 1.0406f, 0), float4(0.8573f, 0.8838f, 1.0411f, 0), float4(0.8500f, 0.8782f, 1.0370f, 0), float4(0.8601f, 0.8857f, 1.0424f, 0),
    float4(0.8613f, 0.8864f, 1.0429f, 0), float4(0.8605f, 0.8860f, 1.0426f, 0), float4(0.8703f, 0.8914f, 1.0463f, 0), float4(0.8584f, 0.8846f, 1.0417f, 0),
    float4(0.8543f, 0.8816f, 1.0396f, 0), float4(0.8499f, 0.8781f, 1.0370f, 0), float4(0.8548f, 0.8820f, 1.0399f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0),
    float4(0.8654f, 0.8889f, 1.0446f, 0), float4(0.8616f, 0.8866f, 1.0431f, 0), float4(0.8575f, 0.8840f, 1.0412f, 0), float4(0.8603f, 0.8858f, 1.0425f, 0),
    float4(0.8564f, 0.8832f, 1.0407f, 0), float4(0.8501f, 0.8783f, 1.0371f, 0), float4(0.8540f, 0.8815f, 1.0394f, 0), float4(0.8680f, 0.8903f, 1.0455f, 0),
    float4(0.8630f, 0.8875f, 1.0436f, 0), float4(0.8651f, 0.8887f, 1.0444f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8557f, 0.8827f, 1.0403f, 0),
    float4(0.8590f, 0.8850f, 1.0419f, 0), float4(0.8513f, 0.8793f, 1.0379f, 0), float4(0.8612f, 0.8863f, 1.0429f, 0), float4(0.8526f, 0.8804f, 1.0386f, 0),
    float4(0.8592f, 0.8851f, 1.0420f, 0), float4(0.8710f, 0.8918f, 1.0465f, 0), float4(0.8496f, 0.8779f, 1.0368f, 0), float4(0.8516f, 0.8796f, 1.0381f, 0),
    float4(0.8539f, 0.8814f, 1.0394f, 0), float4(0.8519f, 0.8798f, 1.0382f, 0), float4(0.8595f, 0.8853f, 1.0421f, 0), float4(0.8534f, 0.8810f, 1.0391f, 0),
    float4(0.8662f, 0.8893f, 1.0449f, 0), float4(0.8523f, 0.8801f, 1.0385f, 0), float4(0.8515f, 0.8795f, 1.0380f, 0), float4(0.8507f, 0.8788f, 1.0375f, 0),
    float4(0.8526f, 0.8804f, 1.0387f, 0), float4(0.8590f, 0.8850f, 1.0419f, 0), float4(0.8544f, 0.8817f, 1.0396f, 0), float4(0.8580f, 0.8843f, 1.0415f, 0),
    float4(0.8619f, 0.8868f, 1.0432f, 0), float4(0.8539f, 0.8814f, 1.0394f, 0), float4(0.8597f, 0.8854f, 1.0422f, 0), float4(0.8565f, 0.8833f, 1.0407f, 0),
    float4(0.8624f, 0.8871f, 1.0434f, 0), float4(0.8581f, 0.8844f, 1.0415f, 0), float4(0.8522f, 0.8800f, 1.0384f, 0), float4(0.8661f, 0.8893f, 1.0448f, 0),
    float4(0.8736f, 0.8930f, 1.0473f, 0), float4(0.8516f, 0.8796f, 1.0381f, 0), float4(0.8719f, 0.8922f, 1.0468f, 0), float4(0.8626f, 0.8872f, 1.0435f, 0),
    float4(0.8505f, 0.8787f, 1.0374f, 0), float4(0.8623f, 0.8871f, 1.0434f, 0), float4(0.8541f, 0.8815f, 1.0395f, 0), float4(0.8565f, 0.8833f, 1.0407f, 0),
    float4(0.8526f, 0.8804f, 1.0386f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8596f, 0.8854f, 1.0422f, 0),
    float4(0.8551f, 0.8823f, 1.0400f, 0), float4(0.8570f, 0.8836f, 1.0410f, 0), float4(0.8536f, 0.8812f, 1.0392f, 0), float4(0.8503f, 0.8784f, 1.0372f, 0),
    float4(0.8535f, 0.8811f, 1.0392f, 0), float4(0.8577f, 0.8841f, 1.0413f, 0), float4(0.8550f, 0.8822f, 1.0400f, 0), float4(0.8814f, 0.8964f, 1.0494f, 0),
    float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8546f, 0.8819f, 1.0397f, 0), float4(0.8543f, 0.8817f, 1.0396f, 0),
    float4(0.8616f, 0.8866f, 1.0431f, 0), float4(0.8690f, 0.8907f, 1.0458f, 0), float4(0.8606f, 0.8860f, 1.0426f, 0), float4(0.8587f, 0.8848f, 1.0418f, 0),
    float4(0.8611f, 0.8863f, 1.0428f, 0), float4(0.8527f, 0.8804f, 1.0387f, 0), float4(0.8571f, 0.8837f, 1.0410f, 0), float4(0.8638f, 0.8879f, 1.0439f, 0),
    float4(0.8531f, 0.8807f, 1.0389f, 0), float4(0.8572f, 0.8838f, 1.0411f, 0), float4(0.8677f, 0.8901f, 1.0454f, 0), float4(0.8661f, 0.8892f, 1.0448f, 0),
    float4(0.8567f, 0.8834f, 1.0408f, 0), float4(0.8648f, 0.8885f, 1.0443f, 0), float4(0.8513f, 0.8793f, 1.0379f, 0), float4(0.8561f, 0.8830f, 1.0405f, 0),
    float4(0.8578f, 0.8842f, 1.0413f, 0), float4(0.8612f, 0.8864f, 1.0429f, 0), float4(0.8535f, 0.8811f, 1.0392f, 0), float4(0.8510f, 0.8790f, 1.0377f, 0),
    float4(0.8603f, 0.8858f, 1.0425f, 0), float4(0.8585f, 0.8847f, 1.0417f, 0), float4(0.8658f, 0.8891f, 1.0447f, 0), float4(0.8605f, 0.8859f, 1.0426f, 0),
    float4(0.8633f, 0.8877f, 1.0438f, 0), float4(0.8563f, 0.8831f, 1.0406f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0),
    float4(0.8819f, 0.8966f, 1.0496f, 0), float4(0.8642f, 0.8882f, 1.0441f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8636f, 0.8878f, 1.0439f, 0),
    float4(0.8572f, 0.8838f, 1.0411f, 0), float4(0.8609f, 0.8862f, 1.0428f, 0), float4(0.8718f, 0.8922f, 1.0467f, 0), float4(0.8564f, 0.8832f, 1.0407f, 0),
    float4(0.8625f, 0.8872f, 1.0434f, 0), float4(0.8513f, 0.8793f, 1.0379f, 0), float4(0.8517f, 0.8797f, 1.0381f, 0), float4(0.8668f, 0.8896f, 1.0451f, 0),
    float4(0.8510f, 0.8790f, 1.0376f, 0), float4(0.8819f, 0.8966f, 1.0495f, 0), float4(0.8496f, 0.8779f, 1.0368f, 0), float4(0.8717f, 0.8921f, 1.0467f, 0),
    float4(0.8550f, 0.8822f, 1.0400f, 0), float4(0.8559f, 0.8829f, 1.0404f, 0), float4(0.8518f, 0.8798f, 1.0382f, 0), float4(0.8534f, 0.8810f, 1.0391f, 0),
    float4(0.8728f, 0.8926f, 1.0470f, 0), float4(0.8558f, 0.8828f, 1.0404f, 0), float4(0.8681f, 0.8903f, 1.0455f, 0), float4(0.8535f, 0.8811f, 1.0392f, 0),
    float4(0.8502f, 0.8784f, 1.0372f, 0), float4(0.8620f, 0.8868f, 1.0432f, 0), float4(0.8610f, 0.8862f, 1.0428f, 0), float4(0.8542f, 0.8816f, 1.0395f, 0),
    float4(0.8504f, 0.8785f, 1.0373f, 0), float4(0.8666f, 0.8895f, 1.0450f, 0), float4(0.8578f, 0.8842f, 1.0414f, 0), float4(0.8559f, 0.8829f, 1.0404f, 0),
    float4(0.8671f, 0.8898f, 1.0452f, 0), float4(0.8538f, 0.8813f, 1.0393f, 0), float4(0.8559f, 0.8829f, 1.0405f, 0), float4(0.8579f, 0.8842f, 1.0414f, 0),
    float4(0.8528f, 0.8805f, 1.0387f, 0), float4(0.8497f, 0.8779f, 1.0368f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0),
    float4(0.8529f, 0.8806f, 1.0388f, 0), float4(0.8608f, 0.8861f, 1.0427f, 0), float4(0.8636f, 0.8878f, 1.0439f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0),
    float4(0.8549f, 0.8821f, 1.0399f, 0), float4(0.8588f, 0.8848f, 1.0418f, 0), float4(0.8688f, 0.8906f, 1.0457f, 0), float4(0.8501f, 0.8783f, 1.0371f, 0),
    float4(0.8610f, 0.8863f, 1.0428f, 0), float4(0.8504f, 0.8786f, 1.0373f, 0), float4(0.8575f, 0.8840f, 1.0412f, 0), float4(0.8556f, 0.8827f, 1.0403f, 0),
    float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8537f, 0.8812f, 1.0393f, 0), float4(0.8633f, 0.8876f, 1.0437f, 0), float4(0.8550f, 0.8822f, 1.0400f, 0),
    float4(0.8617f, 0.8867f, 1.0431f, 0), float4(0.8654f, 0.8888f, 1.0446f, 0), float4(0.8692f, 0.8909f, 1.0459f, 0), float4(0.8528f, 0.8805f, 1.0387f, 0),
    float4(0.8601f, 0.8857f, 1.0424f, 0), float4(0.8633f, 0.8876f, 1.0437f, 0), float4(0.8553f, 0.8824f, 1.0401f, 0), float4(0.8571f, 0.8837f, 1.0411f, 0),
    float4(0.8545f, 0.8818f, 1.0397f, 0), float4(0.8588f, 0.8849f, 1.0419f, 0), float4(0.8638f, 0.8879f, 1.0439f, 0), float4(0.8716f, 0.8921f, 1.0467f, 0),
    float4(0.8637f, 0.8878f, 1.0439f, 0), float4(0.8583f, 0.8845f, 1.0416f, 0), float4(0.8564f, 0.8832f, 1.0407f, 0), float4(0.8584f, 0.8846f, 1.0417f, 0),
    float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8516f, 0.8795f, 1.0380f, 0), float4(0.8551f, 0.8822f, 1.0400f, 0), float4(0.8674f, 0.8899f, 1.0453f, 0),
    float4(0.8526f, 0.8804f, 1.0386f, 0), float4(0.8530f, 0.8807f, 1.0389f, 0), float4(0.8526f, 0.8804f, 1.0387f, 0), float4(0.8599f, 0.8855f, 1.0423f, 0),
    float4(0.8535f, 0.8811f, 1.0392f, 0), float4(0.8501f, 0.8783f, 1.0371f, 0), float4(0.8507f, 0.8788f, 1.0375f, 0), float4(0.8612f, 0.8864f, 1.0429f, 0),
    float4(0.8509f, 0.8790f, 1.0376f, 0), float4(0.8526f, 0.8804f, 1.0387f, 0), float4(0.8602f, 0.8857f, 1.0425f, 0), float4(0.8546f, 0.8819f, 1.0398f, 0),
    float4(0.8612f, 0.8864f, 1.0429f, 0), float4(0.8531f, 0.8807f, 1.0389f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0), float4(0.8722f, 0.8924f, 1.0469f, 0),
    float4(0.8615f, 0.8866f, 1.0430f, 0), float4(0.8519f, 0.8798f, 1.0382f, 0), float4(0.8555f, 0.8825f, 1.0402f, 0), float4(0.8624f, 0.8871f, 1.0434f, 0),
    float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8604f, 0.8859f, 1.0425f, 0), float4(0.8526f, 0.8803f, 1.0386f, 0), float4(0.8593f, 0.8852f, 1.0421f, 0),
    float4(0.8495f, 0.8778f, 1.0367f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8713f, 0.8919f, 1.0466f, 0), float4(0.8536f, 0.8812f, 1.0392f, 0),
    float4(0.8684f, 0.8905f, 1.0456f, 0), float4(0.8549f, 0.8821f, 1.0399f, 0), float4(0.8587f, 0.8848f, 1.0418f, 0), float4(0.8700f, 0.8912f, 1.0461f, 0),
    float4(0.8574f, 0.8839f, 1.0412f, 0), float4(0.8672f, 0.8898f, 1.0452f, 0), float4(0.8677f, 0.8901f, 1.0454f, 0), float4(0.8531f, 0.8807f, 1.0389f, 0),
    float4(0.8524f, 0.8802f, 1.0385f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8699f, 0.8912f, 1.0461f, 0), float4(0.8580f, 0.8843f, 1.0415f, 0),
    float4(0.8553f, 0.8824f, 1.0401f, 0), float4(0.8573f, 0.8839f, 1.0411f, 0), float4(0.8556f, 0.8827f, 1.0403f, 0), float4(0.8734f, 0.8929f, 1.0472f, 0),
    float4(0.8527f, 0.8804f, 1.0387f, 0), float4(0.8543f, 0.8817f, 1.0396f, 0), float4(0.8642f, 0.8882f, 1.0441f, 0), float4(0.8704f, 0.8915f, 1.0463f, 0),
    float4(0.8545f, 0.8819f, 1.0397f, 0), float4(0.8564f, 0.8832f, 1.0407f, 0), float4(0.8662f, 0.8893f, 1.0449f, 0), float4(0.8528f, 0.8805f, 1.0387f, 0),
    float4(0.8535f, 0.8810f, 1.0391f, 0), float4(0.8617f, 0.8867f, 1.0431f, 0), float4(0.8552f, 0.8824f, 1.0401f, 0), float4(0.8513f, 0.8793f, 1.0379f, 0),
    float4(0.8608f, 0.8861f, 1.0427f, 0), float4(0.8590f, 0.8850f, 1.0419f, 0), float4(0.8544f, 0.8818f, 1.0397f, 0), float4(0.8619f, 0.8868f, 1.0432f, 0),
    float4(0.8629f, 0.8874f, 1.0436f, 0), float4(0.8607f, 0.8861f, 1.0427f, 0), float4(0.8602f, 0.8858f, 1.0425f, 0), float4(0.8582f, 0.8845f, 1.0416f, 0),
    float4(0.8549f, 0.8822f, 1.0399f, 0), float4(0.8566f, 0.8834f, 1.0408f, 0), float4(0.8498f, 0.8781f, 1.0369f, 0), float4(0.8618f, 0.8867f, 1.0431f, 0),
    float4(0.8516f, 0.8796f, 1.0380f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8627f, 0.8873f, 1.0435f, 0),
    float4(0.8693f, 0.8909f, 1.0459f, 0), float4(0.8605f, 0.8860f, 1.0426f, 0), float4(0.8580f, 0.8843f, 1.0415f, 0), float4(0.8588f, 0.8848f, 1.0418f, 0),
    float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8639f, 0.8880f, 1.0440f, 0), float4(0.8575f, 0.8840f, 1.0412f, 0), float4(0.8549f, 0.8821f, 1.0399f, 0),
    float4(0.8523f, 0.8801f, 1.0384f, 0), float4(0.8498f, 0.8781f, 1.0369f, 0), float4(0.8504f, 0.8786f, 1.0373f, 0), float4(0.8714f, 0.8920f, 1.0466f, 0),
    float4(0.8763f, 0.8942f, 1.0481f, 0), float4(0.8545f, 0.8818f, 1.0397f, 0), float4(0.8538f, 0.8813f, 1.0393f, 0), float4(0.8572f, 0.8838f, 1.0411f, 0),
    float4(0.8554f, 0.8825f, 1.0402f, 0), float4(0.8543f, 0.8817f, 1.0396f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8563f, 0.8831f, 1.0406f, 0),
    float4(0.8529f, 0.8806f, 1.0388f, 0), float4(0.8693f, 0.8909f, 1.0459f, 0), float4(0.8619f, 0.8868f, 1.0432f, 0), float4(0.8591f, 0.8850f, 1.0420f, 0),
    float4(0.8572f, 0.8838f, 1.0411f, 0), float4(0.8515f, 0.8794f, 1.0380f, 0), float4(0.8504f, 0.8785f, 1.0373f, 0), float4(0.8557f, 0.8827f, 1.0403f, 0),
    float4(0.8620f, 0.8869f, 1.0432f, 0), float4(0.8523f, 0.8801f, 1.0385f, 0), float4(0.8572f, 0.8838f, 1.0411f, 0), float4(0.8603f, 0.8858f, 1.0425f, 0),
    float4(0.8591f, 0.8850f, 1.0420f, 0), float4(0.8633f, 0.8877f, 1.0438f, 0), float4(0.8497f, 0.8780f, 1.0369f, 0), float4(0.8512f, 0.8793f, 1.0378f, 0),
    float4(0.8602f, 0.8857f, 1.0425f, 0), float4(0.8646f, 0.8884f, 1.0442f, 0), float4(0.8613f, 0.8864f, 1.0429f, 0), float4(0.8563f, 0.8831f, 1.0406f, 0),
    float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8533f, 0.8809f, 1.0390f, 0), float4(0.8557f, 0.8827f, 1.0403f, 0), float4(0.8678f, 0.8901f, 1.0454f, 0),
    float4(0.8567f, 0.8834f, 1.0408f, 0), float4(0.8595f, 0.8853f, 1.0421f, 0), float4(0.8552f, 0.8823f, 1.0401f, 0), float4(0.8524f, 0.8802f, 1.0385f, 0),
    float4(0.8666f, 0.8895f, 1.0450f, 0), float4(0.8528f, 0.8805f, 1.0387f, 0), float4(0.8554f, 0.8825f, 1.0402f, 0), float4(0.8553f, 0.8824f, 1.0401f, 0),
    float4(0.8538f, 0.8813f, 1.0393f, 0), float4(0.8729f, 0.8927f, 1.0471f, 0), float4(0.8674f, 0.8899f, 1.0453f, 0), float4(0.8525f, 0.8802f, 1.0386f, 0),
    float4(0.8718f, 0.8922f, 1.0467f, 0), float4(0.8623f, 0.8870f, 1.0433f, 0), float4(0.8550f, 0.8822f, 1.0400f, 0), float4(0.8535f, 0.8810f, 1.0391f, 0),
    float4(0.8511f, 0.8791f, 1.0377f, 0), float4(0.8576f, 0.8841f, 1.0413f, 0), float4(0.8601f, 0.8857f, 1.0424f, 0), float4(0.8504f, 0.8785f, 1.0373f, 0),
    float4(0.8582f, 0.8844f, 1.0415f, 0), float4(0.8535f, 0.8811f, 1.0391f, 0), float4(0.8621f, 0.8869f, 1.0433f, 0), float4(0.8639f, 0.8880f, 1.0440f, 0),
    float4(0.8547f, 0.8820f, 1.0398f, 0), float4(0.8600f, 0.8856f, 1.0424f, 0), float4(0.8575f, 0.8840f, 1.0412f, 0), float4(0.8637f, 0.8878f, 1.0439f, 0),
    float4(0.8587f, 0.8848f, 1.0418f, 0), float4(0.8587f, 0.8848f, 1.0418f, 0), float4(0.8519f, 0.8798f, 1.0383f, 0), float4(0.8531f, 0.8808f, 1.0389f, 0),
    float4(0.8558f, 0.8828f, 1.0404f, 0), float4(0.8568f, 0.8835f, 1.0409f, 0), float4(0.8561f, 0.8830f, 1.0405f, 0), float4(0.8657f, 0.8890f, 1.0447f, 0),
    float4(0.8526f, 0.8804f, 1.0386f, 0), float4(0.8612f, 0.8864f, 1.0429f, 0), float4(0.8541f, 0.8815f, 1.0395f, 0), float4(0.8527f, 0.8805f, 1.0387f, 0),
    float4(0.8526f, 0.8804f, 1.0386f, 0), float4(0.8507f, 0.8788f, 1.0375f, 0), float4(0.8522f, 0.8800f, 1.0384f, 0), float4(0.8539f, 0.8814f, 1.0394f, 0),
    float4(0.8537f, 0.8813f, 1.0393f, 0), float4(0.8556f, 0.8826f, 1.0403f, 0), float4(0.8554f, 0.8825f, 1.0402f, 0), float4(0.8539f, 0.8813f, 1.0393f, 0),
    float4(0.8509f, 0.8790f, 1.0376f, 0), float4(0.8631f, 0.8875f, 1.0437f, 0), float4(0.8513f, 0.8793f, 1.0379f, 0), float4(0.8530f, 0.8807f, 1.0388f, 0),
    float4(0.8596f, 0.8853f, 1.0422f, 0), float4(0.8795f, 0.8956f, 1.0489f, 0), float4(0.8628f, 0.8873f, 1.0435f, 0), float4(0.8621f, 0.8869f, 1.0432f, 0),
    float4(0.8543f, 0.8817f, 1.0396f, 0), float4(0.8596f, 0.8854f, 1.0422f, 0), float4(0.8532f, 0.8809f, 1.0390f, 0), float4(0.8538f, 0.8813f, 1.0393f, 0),
    float4(0.8598f, 0.8855f, 1.0423f, 0), float4(0.8602f, 0.8858f, 1.0425f, 0), float4(0.8673f, 0.8899f, 1.0452f, 0), float4(0.8688f, 0.8907f, 1.0458f, 0),
    float4(0.8559f, 0.8828f, 1.0404f, 0), float4(0.8630f, 0.8875f, 1.0437f, 0), float4(0.8618f, 0.8867f, 1.0431f, 0), float4(0.8579f, 0.8842f, 1.0414f, 0),
    float4(0.8496f, 0.8779f, 1.0368f, 0), float4(0.8556f, 0.8827f, 1.0403f, 0), float4(0.8664f, 0.8894f, 1.0449f, 0), float4(0.8604f, 0.8859f, 1.0425f, 0),
    float4(0.8539f, 0.8814f, 1.0394f, 0), float4(0.8525f, 0.8803f, 1.0386f, 0), float4(0.8548f, 0.8821f, 1.0399f, 0), float4(0.8537f, 0.8812f, 1.0393f, 0),
    float4(0.8556f, 0.8826f, 1.0403f, 0), float4(0.8562f, 0.8830f, 1.0406f, 0), float4(0.8604f, 0.8859f, 1.0426f, 0), float4(0.8672f, 0.8898f, 1.0452f, 0),
    float4(0.8696f, 0.8910f, 1.0460f, 0), float4(0.8509f, 0.8790f, 1.0376f, 0), float4(0.8509f, 0.8790f, 1.0376f, 0), float4(0.8634f, 0.8877f, 1.0438f, 0),
    float4(0.8560f, 0.8829f, 1.0405f, 0), float4(0.8571f, 0.8837f, 1.0410f, 0), float4(0.8680f, 0.8903f, 1.0455f, 0), float4(0.8526f, 0.8804f, 1.0386f, 0),
    float4(0.8642f, 0.8882f, 1.0441f, 0), float4(0.8526f, 0.8803f, 1.0386f, 0), float4(0.8566f, 0.8833f, 1.0408f, 0), float4(0.8715f, 0.8920f, 1.0466f, 0),
    float4(0.8571f, 0.8837f, 1.0410f, 0), float4(0.8619f, 0.8868f, 1.0432f, 0), float4(0.8624f, 0.8871f, 1.0434f, 0), float4(0.8532f, 0.8808f, 1.0390f, 0),
    float4(0.8552f, 0.8824f, 1.0401f, 0), float4(0.8512f, 0.8793f, 1.0378f, 0), float4(0.8566f, 0.8834f, 1.0408f, 0), float4(0.8573f, 0.8839f, 1.0411f, 0),
    float4(0.8625f, 0.8872f, 1.0434f, 0), float4(0.8606f, 0.8860f, 1.0426f, 0), float4(0.8569f, 0.8836f, 1.0409f, 0), float4(0.8632f, 0.8876f, 1.0437f, 0),
    float4(0.8530f, 0.8807f, 1.0388f, 0), float4(0.8532f, 0.8809f, 1.0390f, 0), float4(0.8573f, 0.8838f, 1.0411f, 0), float4(0.8700f, 0.8913f, 1.0462f, 0),
    float4(0.8613f, 0.8864f, 1.0429f, 0), float4(0.8505f, 0.8787f, 1.0374f, 0), float4(0.8621f, 0.8870f, 1.0433f, 0), float4(0.8547f, 0.8820f, 1.0398f, 0),
    float4(0.8540f, 0.8815f, 1.0394f, 0), float4(0.8550f, 0.8822f, 1.0400f, 0), float4(0.8520f, 0.8799f, 1.0383f, 0), float4(0.8638f, 0.8879f, 1.0439f, 0),
    float4(0.8595f, 0.8853f, 1.0421f, 0), float4(0.8538f, 0.8813f, 1.0393f, 0), float4(0.8700f, 0.8913f, 1.0461f, 0), float4(0.8677f, 0.8901f, 1.0454f, 0),
    float4(0.8584f, 0.8846f, 1.0416f, 0), float4(0.8503f, 0.8785f, 1.0372f, 0), float4(0.8541f, 0.8816f, 1.0395f, 0), float4(0.8519f, 0.8798f, 1.0382f, 0),
    float4(0.8532f, 0.8808f, 1.0390f, 0), float4(0.8530f, 0.8807f, 1.0389f, 0), float4(0.8549f, 0.8821f, 1.0399f, 0), float4(0.8536f, 0.8812f, 1.0392f, 0),
    float4(0.8632f, 0.8876f, 1.0437f, 0), float4(0.8498f, 0.8780f, 1.0369f, 0),
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
        state.write(gid.x < 64u ? float4(FLOW_CDF[gid.x], FLOW_PDF[gid.x], FLOW_TAIL[gid.x], 0.0f) : float4(0.0f), gid);
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

// 1 inside the measured field, falling to 0 at its edge: an orbiting ray that samples past the
// data sees the gas fade out instead of the edge values smeared outward. Nothing is invented
// beyond the field.
static float in_data(float2 xy) {
    const float col = STAR_C_TEX.x + xy.x / TEXEL_PC, row = STAR_C_TEX.y + xy.y / TEXEL_PC;
    const float d = min(min(col, float(DATA_W) - 1.0f - col), min(row, float(DATA_H) - 1.0f - row));
    return smoothstep(0.0f, EDGE_TEX, d);
}

// The flow's emission profile, u = h / R0 over 0..3 (state's last row): CDF in .x, PDF in .y,
// and in .z the mean height of the emission above u.
static float3 flow_prof(texture2d<float> st, sampler smp, float u) {
    const float x = (clamp(u, 0.0f, 3.0f) * (63.0f / 3.0f) + 0.5f) / float(DATA_W);
    const float3 p = st.sample(smp, float2(x, (float(3u * DATA_H) + 0.5f) / float(3u * DATA_H + 1u))).xyz;
    return float3(p.x, u > 3.0f ? 0.0f : p.y, p.z);
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
    threadgroup float4 sP[SCAP];   // screen x, y, light normalisation, radius
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
        const float rad = clamp(1.5f + 2.0f * log2(max(peak * EXPOSURE / STRETCH, 1.0f)), 2.0f, 56.0f);
        if (pp.x + rad < tlo.x || pp.x - rad > thi.x || pp.y + rad < tlo.y || pp.y - rad > thi.y) continue;
        const uint slot = atomic_fetch_add_explicit(&nS, 1u, memory_order_relaxed);
        if (slot >= SCAP) continue;
        // where the line from the star toward the camera (-d) crosses the Veil
        const float2 vxy = s.xy - V.d.xy * ((D_VEIL - s.z) / max(-V.d.z, 0.2f));
        const float c = st.sample(smp, st_uv(vxy, 1u)).w + C_FG;
        // each star is dimmed through its own spectrum in X, Y and Z
        const float3 T = exp(-2.3025851f * c * STAR_K[i].xyz);
        // the star image's light sums to 1: Gaussian core (1) + the wing out to the cull radius
        const float wing = 0.0785f * (0.1f * rad * rad) / (1.0f + 0.1f * rad * rad) * 0.85f;
        sP[slot] = float4(pp, 1.0f / (1.0f + wing), rad);
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
    //    lies beyond the last step is added once, sampled where that remainder's light comes
    //    from on average (its mean height), so a ray from Earth still gets exactly the
    //    measured line brightness and a slanted ray sees the high gas where it is.
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
            const float3 p1 = flow_prof(st, smp, v1);
            const float avg = abs(dv) > 1e-3f ? (p1.x - P0) / dv : flow_prof(st, smp, 0.5f * (v0 + v1)).y;
            const float w = avg * dl / Rv;
            const float e = in_data(o.xy + 0.5f * (t0 + t1) * d.xy);
            I_ha += w * e * 0.5f * (s0.x + s1.x);
            I_o3 += w * e * 0.5f * (s0.y + s1.y);
            t0 = t1; s0 = s1; v0 = v1; P0 = p1.x; step *= 1.75f;
            if (v1 >= 3.0f) break;
        }
        const float tail = 1.0f - P0;
        const float v_tail = flow_prof(st, smp, v0).z;
        const float t_tail = t0 - (v_tail - v0) * max(s0.w, 1e-4f) / max(-dz, 0.3f);
        const float4 st_tail = st.sample(smp, st_uv(o.xy + t_tail * d.xy, 0u));
        const float e_tail = in_data(o.xy + t_tail * d.xy);
        I_ha += tail * e_tail * st_tail.x;
        I_o3 += tail * e_tail * st_tail.y;
    }

    // 3) the front sheet ([N II], [S II], [O I]) seen at its angle
    const float2 hit_xy = o.xy + t_hit * d.xy;
    const float4 sheet = st.sample(smp, st_uv(hit_xy, 1u)) * float4(float3(in_data(hit_xy)), 1.0f);
    const float4 nb = st.sample(smp, st_uv(hit_xy, 2u));
    const float3 nrm = nb.xyz;
    const float graze = min(nrm.z / max(abs(dot(nrm, d)), 1e-3f), GRAZE_MAX);

    // 4) the Veil and the ISM in front
    const float t_veil = (D_VEIL - o.z) / dz;
    const float2 veil_xy = o.xy + t_veil * d.xy;
    const float c_veil = st.sample(smp, st_uv(veil_xy, 1u)).w;   // stays within 4 mpc of the data
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
        // (the wing fades out before the cull radius, so bright stars have no rim)
        const float fade = 1.0f - smoothstep(0.36f, 1.0f, r2 / (P.w * P.w));
        const float psf = 0.2487f * exp(-r2 * 0.78125f) + fade * 0.0025f / (1.0f + r2 * 0.1f) / (1.0f + r2 * 0.1f);
        star += sC[j].xyz * (psf * P.z);
    }
    rgb += xyz_to_srgb_lin(star) * EXPOSURE;

    out.write(float4(argus_srgb(stretch(rgb)), 1.0f), gid);
}
