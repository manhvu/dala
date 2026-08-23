defmodule Dala.Ui.ScanTest do
  use ExUnit.Case, async: true

  alias Dala.Ui.Scan

  describe "parse/1 URLs" do
    test "parses https URLs" do
      assert %{type: :url, value: "https://example.com/page"} =
               Scan.parse("https://example.com/page")
    end

    test "parses http, ftp, and ftps URLs" do
      assert %{type: :url} = Scan.parse("http://example.com")
      assert %{type: :url} = Scan.parse("ftp://files.example.com")
      assert %{type: :url} = Scan.parse("ftps://files.example.com")
    end
  end

  describe "parse/1 WiFi" do
    test "parses WPA credentials with hidden flag" do
      assert %{
               type: :wifi,
               value: %{
                 ssid: "MyNet",
                 password: "secret",
                 security: :wpa,
                 hidden: true
               }
             } = Scan.parse("WIFI:T:WPA;S:MyNet;P:secret;H:true;;")
    end

    test "maps security types" do
      assert %{value: %{security: :wep}} = Scan.parse("WIFI:T:WEP;S:net;;")
      assert %{value: %{security: :open}} = Scan.parse("WIFI:T:nopass;S:net;;")
      assert %{value: %{security: :unknown}} = Scan.parse("WIFI:T:???;S:net;;")
    end

    test "defaults hidden to false and missing fields to empty strings" do
      assert %{value: %{ssid: "", password: "", hidden: false}} = Scan.parse("WIFI:T:WPA;;;")
    end

    test "accepts lowercase prefix" do
      assert %{type: :wifi} = Scan.parse("wifi:T:WPA;S:net;;")
    end
  end

  describe "parse/1 email" do
    test "parses plain mailto" do
      assert %{type: :email, value: %{email: "user@example.com", subject: "", body: ""}} =
               Scan.parse("mailto:user@example.com")
    end

    test "decodes subject and body params" do
      assert %{type: :email, value: %{subject: "Hi there", body: "Line one"}} =
               Scan.parse("mailto:user@example.com?subject=Hi%20there&body=Line%20one")
    end
  end

  describe "parse/1 phone and sms" do
    test "parses tel:" do
      assert %{type: :phone, value: %{number: "+1234567890"}} = Scan.parse("tel:+1234567890")
    end

    test "parses smsto: with message" do
      assert %{type: :sms, value: %{number: "+1234", message: "hello"}} =
               Scan.parse("smsto:+1234:hello")
    end

    test "parses smsto: without message" do
      assert %{type: :sms, value: %{number: "+1234", message: ""}} = Scan.parse("smsto:+1234")
    end
  end

  describe "parse/1 geo" do
    test "parses coordinates without query" do
      assert %{type: :geo, value: %{lat: 37.78, lon: -122.4, altitude: nil, query: ""}} =
               Scan.parse("geo:37.78,-122.40")
    end

    test "parses query and altitude" do
      assert %{
               type: :geo,
               value: %{lat: 37.78, lon: -122.4, altitude: 100.5, query: "Golden+Gate"}
             } =
               Scan.parse("geo:37.78,-122.40?q=Golden+Gate&altitude=100.5")
    end

    test "non-numeric coordinates parse to nil" do
      assert %{value: %{lat: nil, lon: nil}} = Scan.parse("geo:abc,def")
    end
  end

  describe "parse/1 vCard" do
    @vcard """
    BEGIN:VCARD
    VERSION:3.0
    N:Doe;John;;
    FN:John Doe
    TEL;TYPE=CELL:+15551234567
    EMAIL:john@example.com
    ORG:Acme Inc
    TITLE:Engineer
    URL:https://johndoe.example.com
    ADR:;;123 Main St;Springfield;IL;62701;USA
    END:VCARD
    """

    test "extracts all fields" do
      assert %{
               type: :vcard,
               value: %{
                 name: "John Doe",
                 phone: "+15551234567",
                 email: "john@example.com",
                 org: "Acme Inc",
                 title: "Engineer",
                 url: "https://johndoe.example.com",
                 address: ", , 123 Main St, Springfield, IL, 62701, USA"
               }
             } = Scan.parse(@vcard)
    end

    test "falls back to FN when N is absent" do
      vcard = "BEGIN:VCARD\nFN:Jane Roe\nEND:VCARD"
      assert %{value: %{name: "Jane Roe"}} = Scan.parse(vcard)
    end

    test "missing fields default to empty strings" do
      vcard = "BEGIN:VCARD\nFN:X\nEND:VCARD"

      assert %{value: %{phone: "", email: "", org: "", title: "", url: "", address: ""}} =
               Scan.parse(vcard)
    end
  end

  describe "parse/1 VEvent" do
    test "extracts calendar fields" do
      event = """
      BEGIN:VEVENT
      SUMMARY:Standup
      DTSTART:20260101T090000Z
      DTEND:20260101T091500Z
      LOCATION:Room 4
      DESCRIPTION:Daily sync
      END:VEVENT
      """

      assert %{
               type: :vevent,
               value: %{
                 summary: "Standup",
                 start: "20260101T090000Z",
                 end: "20260101T091500Z",
                 location: "Room 4",
                 description: "Daily sync"
               }
             } = Scan.parse(event)
    end

    test "missing fields default to empty strings" do
      event = "BEGIN:VEVENT\nSUMMARY:Lunch\nEND:VEVENT"

      assert %{value: %{start: "", end: "", location: "", description: ""}} =
               Scan.parse(event)
    end
  end

  describe "parse/1 text fallback" do
    test "returns raw text for unrecognised content" do
      assert %{type: :text, value: "just some words"} = Scan.parse("just some words")
    end
  end
end
