#!/usr/bin/env ruby
# Fills in the App Store listing for Fishy from AppStore/metadata.json and uploads the screenshots in
# AppStore/screenshots, replacing what is there. Run it again after changing either.
#
# Based on Detent's scripts/appstore.rb, extended for more than one platform: each platform in
# metadata.json "platforms" (IOS, TV_OS) gets its version (created if missing), text, build, review
# details and screenshots. App information (subtitle, privacy policy, categories, age rating), price and
# availability are shared by all platforms.
#
# Also attaches the newest processed build for each platform, answers the age rating questions (all
# "none"), and, the first time only, makes the app free in every territory.
#
# What the API cannot do, and is left for App Store Connect: the App Privacy answers and pressing
# "Add for Review". The review contact comes from Config/testflight.env (REVIEW_* in the example).
#
# Uses the same App Store Connect API key as scripts/testflight.sh (Config/testflight.env).
#
# Usage: scripts/appstore.rb [--no-screenshots]
require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"

Encoding.default_external = Encoding::UTF_8
ROOT = File.expand_path("..", __dir__)
BUNDLE_ID = "com.colinbm.fishy"
META = JSON.parse(File.read(File.join(ROOT, "AppStore/metadata.json")))

env = File.readlines(File.join(ROOT, "Config/testflight.env")).filter_map do |line|
  next if line.strip.start_with?("#") || !line.include?("=")
  key, value = line.strip.split("=", 2)
  [key, value.gsub("$HOME", Dir.home)]
end.to_h

def token(env)
  base64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
  now = Time.now.to_i
  payload = { iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }
  if env["ASC_ISSUER_ID"].to_s.empty? then payload[:sub] = "user" else payload[:iss] = env["ASC_ISSUER_ID"] end
  input = "#{base64.({ alg: "ES256", kid: env["ASC_KEY_ID"], typ: "JWT" }.to_json)}.#{base64.(payload.to_json)}"
  key = OpenSSL::PKey.read(File.read(env["ASC_KEY_PATH"]))
  # JWT wants the raw r||s signature, not OpenSSL's DER.
  der = OpenSSL::ASN1.decode(key.sign(OpenSSL::Digest::SHA256.new, input))
  "#{input}.#{base64.(der.value.map { |n| n.value.to_s(2).rjust(32, "\0")[-32, 32] }.join)}"
end

JWT = token(env)

# Returns nil for a 404 when `missing_ok`, for things that may not have been set up yet.
def api(method, path, body = nil, missing_ok: false)
  uri = URI(path.start_with?("http") ? path : "https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
  request["Authorization"] = "Bearer #{JWT}"
  if body
    request["Content-Type"] = "application/json"
    request.body = body.to_json
  end
  response = Net::HTTP.start(uri.host, 443, use_ssl: true) { |http| http.request(request) }
  return nil if missing_ok && response.code == "404"
  abort "#{method.upcase} #{path}: HTTP #{response.code}\n#{response.body}" unless response.is_a?(Net::HTTPSuccess)
  response.body.to_s.empty? ? {} : JSON.parse(response.body.force_encoding("UTF-8"))
end

def patch(type, id, attributes)
  api(:patch, "/v1/#{type}/#{id}", { data: { type: type, id: id, attributes: attributes } })
end

def link(type, id, relationship, related_type, related_id)
  api(:patch, "/v1/#{type}/#{id}/relationships/#{relationship}", { data: { type: related_type, id: related_id } })
end

app = api(:get, "/v1/apps?filter[bundleId]=#{BUNDLE_ID}")["data"].first or abort "No app with bundle ID #{BUNDLE_ID}"
app_id = app["id"]
locale = META["locale"] || app["attributes"]["primaryLocale"]
editable = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY]

# The version number to create a missing platform's version with: the one the app's builds use.
version_string = File.read(File.join(ROOT, "Fishy.xcodeproj/project.xcproj"))[/"MARKETING_VERSION": "([^"]+)"/, 1] || "1.0"

# MARK: Shared: app information, age rating, price, availability.

info = api(:get, "/v1/apps/#{app_id}/appInfos")["data"].find { |i| editable.include?(i["attributes"]["state"]) } ||
       api(:get, "/v1/apps/#{app_id}/appInfos")["data"].first
info_localization = api(:get, "/v1/appInfos/#{info["id"]}/appInfoLocalizations")["data"]
                    .find { |l| l["attributes"]["locale"] == locale } or abort "No #{locale} app information localization"
patch("appInfoLocalizations", info_localization["id"], META.slice("subtitle", "privacyPolicyUrl"))
categories = %w[primaryCategory primarySubcategoryOne primarySubcategoryTwo secondaryCategory]
             .select { |key| META[key] }
             .to_h { |key| [key, { data: { type: "appCategories", id: META[key] } }] }
api(:patch, "/v1/appInfos/#{info["id"]}", { data: { type: "appInfos", id: info["id"], relationships: categories } })
puts "Subtitle, privacy policy URL and categories set"

declaration = api(:get, "/v1/appInfos/#{info["id"]}/ageRatingDeclaration")["data"]
none = %w[alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated gunsOrOtherWeapons
          medicalOrTreatmentInformation profanityOrCrudeHumor sexualContentGraphicAndNudity
          sexualContentOrNudity horrorOrFearThemes matureOrSuggestiveThemes violenceCartoonOrFantasy
          violenceRealisticProlongedGraphicOrSadistic violenceRealistic]
no = %w[advertising gambling healthOrWellnessTopics lootBox messagingAndChat parentalControls ageAssurance
        socialMedia unrestrictedWebAccess userGeneratedContent]
answers = none.to_h { |k| [k, "NONE"] }.merge(no.to_h { |k| [k, false] })
                .select { |k, _| declaration["attributes"].key?(k) }
patch("ageRatingDeclarations", declaration["id"], answers)
puts "Age rating questions answered"

# Price: free, the first time only.
has_price = api(:get, "/v1/apps/#{app_id}/appPriceSchedule?include=manualPrices", missing_ok: true)
            &.fetch("included", [])&.any?
unless has_price
  free = api(:get, "/v1/apps/#{app_id}/appPricePoints?filter[territory]=GBR&limit=200")["data"]
         .find { |p| p["attributes"]["customerPrice"].to_f.zero? } or abort "No free price point"
  api(:post, "/v1/appPriceSchedules", {
    data: { type: "appPriceSchedules", relationships: {
      app: { data: { type: "apps", id: app_id } },
      baseTerritory: { data: { type: "territories", id: "GBR" } },
      manualPrices: { data: [{ type: "appPrices", id: "${free}" }] } } },
    included: [{ type: "appPrices", id: "${free}", attributes: { startDate: nil },
                 relationships: { appPricePoint: { data: { type: "appPricePoints", id: free["id"] } } } }]
  })
  puts "Price set to free"
end

# Availability: every territory, the first time only.
has_availability = api(:get, "/v1/apps/#{app_id}/appAvailabilityV2", missing_ok: true)
unless has_availability
  territories = api(:get, "/v1/territories?limit=200")["data"].map { |t| t["id"] }
  api(:post, "/v2/appAvailabilities", {
    data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true }, relationships: {
      app: { data: { type: "apps", id: app_id } },
      territoryAvailabilities: { data: territories.map { |t| { type: "territoryAvailabilities", id: "${#{t}}" } } } } },
    included: territories.map { |t|
      { type: "territoryAvailabilities", id: "${#{t}}", attributes: { available: true },
        relationships: { territory: { data: { type: "territories", id: t } } } }
    }
  })
  puts "Available in #{territories.size} territories"
end

# MARK: Per platform: version, text, build, review details, screenshots.

contact = { contactFirstName: "REVIEW_FIRST_NAME", contactLastName: "REVIEW_LAST_NAME",
            contactEmail: "REVIEW_EMAIL", contactPhone: "REVIEW_PHONE" }
          .transform_values { |key| env[key].to_s.strip }.reject { |_, value| value.empty? }

META["platforms"].each do |platform, settings|
  puts "== #{platform}"
  version = api(:get, "/v1/apps/#{app_id}/appStoreVersions?filter[platform]=#{platform}")["data"]
            .find { |v| editable.include?(v["attributes"]["appStoreState"]) }
  unless version
    version = api(:post, "/v1/appStoreVersions", { data: { type: "appStoreVersions",
      attributes: { platform: platform, versionString: version_string },
      relationships: { app: { data: { type: "apps", id: app_id } } } } })["data"]
    puts "Created version #{version_string}"
  end
  version_id = version["id"]
  puts "Version #{version["attributes"]["versionString"]} (#{version["attributes"]["appStoreState"]})"

  # Version: copyright and build.
  patch("appStoreVersions", version_id, { copyright: META["copyright"] })
  build = api(:get, "/v1/builds?filter[app]=#{app_id}&filter[preReleaseVersion.platform]=#{platform}" \
                    "&filter[processingState]=VALID&sort=-uploadedDate&limit=1")["data"].first
  if build
    link("appStoreVersions", version_id, "build", "builds", build["id"])
    puts "Build #{build["attributes"]["version"]} attached"
  else
    puts "No processed build to attach yet"
  end

  # Version text.
  localization = api(:get, "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations")["data"]
                 .find { |l| l["attributes"]["locale"] == locale }
  localization ||= api(:post, "/v1/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations",
    attributes: { locale: locale },
    relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })["data"]
  patch("appStoreVersionLocalizations", localization["id"],
        META.slice("description", "keywords", "promotionalText", "supportUrl", "marketingUrl"))
  puts "Description, keywords, promotional text and URLs set"

  # Review notes, and the review contact if Config/testflight.env has one (it stays out of the
  # repository: see testflight.env.example).
  review = api(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail", missing_ok: true)&.dig("data")
  existing = (review&.dig("attributes") || {}).slice("contactFirstName", "contactLastName",
                                                      "contactEmail", "contactPhone")
                                               .transform_keys(&:to_sym).reject { |_, value| value.to_s.empty? }
  review_attributes = existing.merge(contact).merge(notes: META["reviewNotes"], demoAccountRequired: false)
  if review && review_attributes.count { |key, _| key.start_with?("contact") } < 4
    # Once created, the review details can only be changed along with the full contact.
    puts "Review notes not updated: add REVIEW_FIRST_NAME, REVIEW_LAST_NAME, REVIEW_EMAIL and REVIEW_PHONE " \
         "(+44 …) to Config/testflight.env, or fill in the contact in App Store Connect"
  elsif review
    patch("appStoreReviewDetails", review["id"], review_attributes)
    puts "Review notes and contact set"
  else
    api(:post, "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: review_attributes,
      relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })
    puts "Review notes set"
  end

  next if ARGV.include?("--no-screenshots")

  # Screenshots: replace each display type's set with the files in its folder, in name order.
  sets = api(:get, "/v1/appStoreVersionLocalizations/#{localization["id"]}/appScreenshotSets")["data"]
  settings["screenshots"].each do |display_type, folder|
    files = Dir[File.join(ROOT, folder, "*.png")].sort
    next if files.empty?

    set = sets.find { |s| s["attributes"]["screenshotDisplayType"] == display_type } ||
          api(:post, "/v1/appScreenshotSets", { data: { type: "appScreenshotSets",
            attributes: { screenshotDisplayType: display_type },
            relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations",
                                                                    id: localization["id"] } } } } })["data"]
    api(:get, "/v1/appScreenshotSets/#{set["id"]}/appScreenshots")["data"].each do |old|
      api(:delete, "/v1/appScreenshots/#{old["id"]}")
    end

    files.each do |file|
      data = File.binread(file)
      shot = api(:post, "/v1/appScreenshots", { data: { type: "appScreenshots",
        attributes: { fileName: File.basename(file), fileSize: data.bytesize },
        relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set["id"] } } } } })["data"]
      shot["attributes"]["uploadOperations"].each do |operation|
        uri = URI(operation["url"])
        request = Net::HTTP.const_get(operation["method"].capitalize).new(uri)
        operation["requestHeaders"].each { |header| request[header["name"]] = header["value"] }
        request.body = data.byteslice(operation["offset"], operation["length"])
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
        abort "Uploading #{file}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      end
      patch("appScreenshots", shot["id"], { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) })
      puts "#{display_type}: uploaded #{File.basename(file)}"
    end
  end
end

puts "Done. Still to do in App Store Connect: App Privacy, and Add for Review."
