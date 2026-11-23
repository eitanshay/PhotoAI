import Foundation

/// All prompt text, ported from the web version (ES-07 web, Oct 2026).
public enum Prompts {

    public static let playbookRefine = """
    portrait (single person, profile picture, headshot): soft large key light from slightly above and to one side, gentle fill, clean catchlights in the eyes, even natural skin tone with realistic texture and only light blemish cleanup, subtle background separation and shallow depth of field like an 85mm lens, tidy background, flattering exposure. The face, expression, hair, age and likeness must stay exactly the same.
    group (several people): even soft light across all faces, balanced exposure, consistent skin tones, clean background, everyone sharp, no changes to anyone's face or position.
    food: soft directional window light, appetizing saturated but natural color, glossy highlights where food is moist, gentle steam or sheen only if already present, shallow depth of field on the hero item, clean surface, minor crumbs and distractions tidied, rich contrast.
    car (vehicles, motorcycles): crisp polished paint with clean controlled reflections, golden-hour or large softbox look, deep saturated color, sharp wheels and badges, clean uncluttered surroundings, subtle contrast on bodywork. Make, model, color, plate and design must not change.
    landscape (nature, travel, outdoor scenery): balanced exposure with recovered highlights and lifted shadows, golden or soft light, clear deep sky, haze reduced, natural vivid color, crisp detail, pleasing tonal depth.
    architecture (interior, real estate, buildings): bright even light, true white balance, straightened verticals, clean tidy rooms, window highlights controlled, wide-angle real-estate quality.
    product (objects, gear, still life): clean softbox lighting, accurate color, crisp edges, subtle reflections, neutral uncluttered background, high detail on materials.
    pet (animals): bright catchlights, sharp fur detail, soft background separation, warm natural light, true coat color.
    street (candid, city, events, night): controlled contrast, clean highlights, rich color, reduced noise, cinematic but natural light, keep the moment authentic.
    other: general professional polish: balanced exposure, accurate color, clean light, reduced noise, crisp detail.
    """

    public static let playbookStudio = """
    portrait (single person, profile picture, headshot): cover shoot for a high-end fashion or lifestyle magazine. Seamless paper or textured studio backdrop in a color that flatters the skin and clothing, large beauty dish or octabox key slightly above and off axis, silver reflector fill under the chin, strip light rim to separate hair and shoulders, controlled specular highlights, crisp catchlights. 85 to 105mm lens at f/2 to f/4, camera at eye level. Retouching is natural and texture-preserving: never reshape any facial or body feature. Polished wardrobe and a deliberate color palette.
    group (several people): editorial group portrait in a studio or on a designed set, large soft main light plus a hair light, clean seamless or textured backdrop, everyone sharp, coordinated palette, wardrobe pressed and polished, no face or body reshaping.
    food: cookbook cover or Bon Appetit grade food photography. Plate styled on a premium surface chosen to complement the dish (aged wood, marble, ceramic, linen), one large softbox from back left with a white bounce card, steam or glisten where it belongs, fresh garnish, intentional props like cutlery and a napkin in soft focus, 90mm lens at f/4 with shallow depth of field, rich appetizing color.
    car (cars, motorcycles): automotive magazine cover shoot. Dark or white infinity studio, or wet asphalt at blue hour. Huge overhead softbox and long strip lights tracing the body lines, deep polished paint with controlled reflections, glossy floor reflection, rim light on the shoulders, wheels clean and aligned, 35 to 70mm lens at a low camera height.
    landscape (nature, travel, outdoor scenery): National Geographic or travel magazine hero shot. Golden hour or blue hour light, dramatic but natural sky, luminous layered depth, recovered highlights, rich color grade, crisp foreground detail, strong leading lines.
    architecture (interior, real estate, buildings): Architectural Digest feature. Twilight or bright airy daylight, perfectly straight verticals, 24mm tilt-shift look, styled interior with layered warm practical lights, controlled window and glass reflections, clean uncluttered surfaces.
    product (objects, gear, still life): premium commercial hero shot. Seamless sweep, large softbox with gradient strips for edge highlights, subtle floor reflection, razor sharp macro detail, accurate materials and branding.
    pet (animals): studio pet portrait for a magazine. Seamless backdrop in a complementary color, soft key with a rim light for fur detail, bright catchlights, 85mm lens, true coat color.
    street (candid, city, events, night): editorial photo story. Cinematic controlled color, dramatic but believable light, refined contrast, strong composition, authentic moment.
    other: high-end commercial shoot. Choose the most flattering studio or location setup for the subject, with a full lighting plan, lens choice, backdrop and grade.
    """

    public static let identityLock = "Identity lock: the main subject must stay unmistakably the same: same person or people (face, features, skin tone, hair, age, body proportions, expression), same animal, same dish and ingredients, same vehicle (make, model, color, trim), same product (shape, materials, branding, text). Everything else may be reimagined. Keep the output aspect ratio the same as the attached photo. Photorealistic photograph, not an illustration. No added text, borders or watermarks. Output one image."

    public static let guardRefine = "Hard constraints: keep the exact same subject(s), identity, faces, expressions, pose, objects, logos, text, composition, framing and aspect ratio. Do not add or remove people or objects. Do not add text, borders or watermarks. Output one photographic image."

    static let peopleRules = "If people are present, these rules override everything else: the \"prompt\" must never describe, mention or change any person's face, body, age, hair, skin or expression. Do not use words such as flawless, perfect, beautiful, gorgeous, model, symmetrical, youthful, slim or glamorous. Only specify the set, lighting, camera, color grade, wardrobe polish and natural texture-preserving retouching."

    static let categoryList = "\"portrait\",\"group\",\"food\",\"car\",\"landscape\",\"architecture\",\"product\",\"pet\",\"street\",\"other\""

    static let sharedKeys = """
     "subject": a short noun phrase naming the main subject (max 8 words),
     "people": integer, how many people have a visible face (0 if none),
     "faces": array of up to 4 boxes [ymin,xmin,ymax,xmax], each coordinate 0 to 1000 relative to the image, tight around the largest visible faces including forehead and chin, empty array if no people,
     "identity": if people are present, a neutral description (max 30 words) of the main person's or people's identifying features: approximate age range, hair color and style, facial hair, glasses, skin tone, distinguishing marks; otherwise an empty string,
    """

    /// Instruction for the text model that reads the photo and writes the brief.
    public static func analyzeInstruction(intensity: Intensity) -> String {
        if intensity == .refine {
            return """
            You are a senior photo retoucher and art director. Look at the attached photo and decide what kind of photo it is, then write the brief an image-editing model will follow to re-render this exact photo as if a professional photographer had shot it.

            Genre guidance, use the matching entry:
            \(playbookRefine)

            \(peopleRules)

            Return ONLY JSON, no code fences, with exactly these keys:
            {"category": one of \(categoryList),
            \(sharedKeys)
             "issues": array of up to 4 short strings naming what is weak in this photo (lighting, color, noise, clutter, framing and so on),
             "prompt": 70 to 140 words, imperative, concrete photographic language (light direction and quality, color temperature, contrast, depth of field, sharpness, background cleanliness, retouch level). Fix the listed issues. Name the subject in the prompt. Do not mention the style preset. Do not use bullet points.}

            Rules for "prompt": it must only improve lighting, exposure, white balance, color, sharpness, noise, depth of field, background tidiness and overall polish. It must not change who or what is in the photo, their pose, the composition or the framing.
            """
        }
        let level = intensity == .studio
            ? "STUDIO. Rebuild the lighting, background and retouching completely, with a clean studio or equivalent set. Keep the original pose, composition, camera angle and framing."
            : "MAGAZINE. Reimagine freely. You may change the set, background, camera angle, lens, crop, styling, wardrobe polish, props and mood to reach a cover-worthy result. Only the main subject's identity is locked."
        return """
        You are the creative director of a high-end magazine. Look at the attached photo and decide what kind of photo it is. Then write the SHOT BRIEF an image model will follow to create a brand-new, flagship quality photograph of the same main subject, as if an elite photographer had shot it in a professional studio or on the ideal set for a magazine cover. This is a full reimagining of the picture, not a filter and not a light touch-up: rebuild the whole image around the subject.

        Intensity: \(level)

        Genre guidance, use the matching entry and push it further:
        \(playbookStudio)

        \(peopleRules)

        Return ONLY JSON, no code fences, with exactly these keys:
        {"category": one of \(categoryList),
        \(sharedKeys)
         "issues": array of up to 4 short strings naming what is weak in the original photo,
         "prompt": 140 to 210 words, imperative, concrete, written like a call sheet. Open by naming the subject. Then specify in prose: the set and backdrop (specific materials and colors), the full lighting plan (key, fill, rim or kicker, modifiers, direction, quality, contrast ratio), camera and lens (focal length, aperture, camera height), color palette and grade, styling and retouching level, and the mood. Make bold, specific choices. Do not mention any style preset. Do not use bullet points. Do not restate identity constraints, they are added automatically.}
        """
    }

    public static func fallbackBrief(intensity: Intensity) -> String {
        intensity == .refine
            ? "Re-render this photo as a professional photographer would have shot it: balanced exposure, accurate color, clean soft light, reduced noise, crisp detail and a tidy background, keeping everything in the scene exactly as it is."
            : "Create a magazine cover quality photograph of the main subject on a seamless studio backdrop in a complementary color. Large softbox key from camera left, soft fill, a strip light rim for separation, 85mm lens at f/2.8, camera at the subject eye level, rich controlled color grade, premium retouching with natural texture, polished and confident mood."
    }

    /// The people lock paragraph, or empty when no people are present.
    public static func peopleLock(analysis: Analysis, cropCount: Int, retouch: Retouch) -> String {
        guard analysis.hasPeople else { return "" }
        var s = "PEOPLE LOCK: Image 1 is the photograph to edit."
        if cropCount > 0 {
            s += cropCount > 1
                ? " Images 2 to \(cropCount + 1) are close-ups of the faces in it, given as identity references."
                : " Image 2 is a close-up of the faces in it, given as identity references."
        }
        s += " Every person must remain exactly who they are: keep each face, head shape, bone structure, eyes, nose, mouth, ears, skin tone"
        s += retouch == .off ? " and texture" : ""
        s += ", hair, facial hair, age, expression, gaze direction and body proportions identical to the original photo"
        s += cropCount > 0 ? " and the close-ups" : ""
        s += ". "
        if !analysis.identity.isEmpty {
            s += "Identifying features that must be preserved: \(analysis.identity). "
        }
        if retouch == .off {
            s += "Do not beautify, slim, smooth skin, change age, change expression, or replace anyone with a similar looking different person. Only the environment, lighting, camera look, color grade and wardrobe polish may change."
        } else {
            s += "Do not slim, reshape or otherwise alter any facial or body feature, change age, change expression, or replace anyone with a similar looking different person. "
            s += retouch.instruction
            s += " Apart from this retouching, only the environment, lighting, camera look, color grade and wardrobe polish may change."
        }
        return s
    }

    /// The full text sent to the image model.
    public static func imagePrompt(brief: String, preset: StylePreset, intensity: Intensity, retouch: Retouch,
                                   analysis: Analysis, cropCount: Int, strictDifferences: String?) -> String {
        let people = analysis.hasPeople
        let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let style = "Style direction: \(preset.clause)"
        let lock = peopleLock(analysis: analysis, cropCount: cropCount, retouch: retouch)
        var retry = ""
        if let strict = strictDifferences, !strict.isEmpty {
            retry = "\n\nThe previous attempt failed an identity check. Differences found: \(strict). Correct this: the faces must match the original exactly."
        }
        let tail = people ? "\n\nReminder: the people must look identical to the original photo." : ""

        if intensity == .refine {
            return "\(trimmed)\n\n\(style)\n\n\(guardRefine)\(people ? "\n\n" + lock : "")\(retry)\(tail)"
        }
        if people {
            return "Edit the attached photograph as described below.\n\n\(lock)\n\n\(trimmed)\n\n\(style)\n\n\(identityLock)\(retry)\(tail)"
        }
        return "Use the attached photo as the reference for the main subject. Create a brand-new professional photograph of that exact subject, shot as described below.\n\n\(trimmed)\n\n\(style)\n\n\(identityLock)"
    }

    public static func verifyInstruction(cropCount: Int) -> String {
        """
        You are a forensic face comparison reviewer. The first \(cropCount) image(s) are close-ups of the people in an ORIGINAL photo. The last image is a NEW photo that should show the same people. Decide whether each original person appears in the new photo with an identical face. Judge only facial identity: bone structure, eyes, nose, mouth, ears, hairline, facial hair, age and skin tone. Ignore lighting, background, clothing, color grade, sharpness, skin smoothing, blemish removal and teeth whitening.
        Return ONLY JSON: {"score": integer 1 to 10 (10 = indistinguishable, 7 = clearly the same person with small differences, 4 = resembles but is a different person, 1 = unrelated), "differences": array of up to 4 short strings naming specific facial differences}.
        """
    }
}
