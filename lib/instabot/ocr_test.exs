defmodule Instabot.OCRTest do
  use ExUnit.Case, async: false

  alias Instabot.OCR

  describe "available?/0" do
    test "returns boolean based on tesseract availability" do
      assert is_boolean(OCR.available?())
    end
  end

  describe "extract_text/1" do
    test "returns error for non-existent file or missing tesseract" do
      result = OCR.extract_text("/nonexistent/path.png")
      assert {:error, reason} = result
      assert :file_not_found == reason
    end

    test "extracts text through the tesseract executable" do
      with_fake_tesseract("""
      #!/bin/sh
      printf '%s\\n' 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext'
      printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t95\tStory'
      printf '%s\\n' '5\t1\t1\t1\t1\t2\t0\t0\t10\t10\t90\theadline'
      exit 0
      """)

      image_path = temp_image_path()
      File.write!(image_path, "image")

      assert {:ok, "Story headline"} == OCR.extract_text(image_path)
    end

    test "does not include tesseract stderr diagnostics in extracted text" do
      with_fake_tesseract("""
      #!/bin/sh
      echo "Estimating resolution as 242" >&2
      printf '%s\\n' 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext'
      printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t95\tOPEN'
      printf '%s\\n' '5\t1\t1\t1\t1\t2\t0\t0\t10\t10\t94\tHOURS'
      exit 0
      """)

      image_path = temp_image_path()
      File.write!(image_path, "image")

      assert {:ok, "OPEN HOURS"} == OCR.extract_text(image_path)
    end

    test "filters low confidence visual noise while preserving emails" do
      with_fake_tesseract("""
      #!/bin/sh
      printf '%s\\n' 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext'
      printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t30\tInstagnam'
      printf '%s\\n' '5\t1\t1\t1\t2\t1\t0\t0\t10\t10\t92\tLooking'
      printf '%s\\n' '5\t1\t1\t1\t2\t2\t0\t0\t10\t10\t92\tfor'
      printf '%s\\n' '5\t1\t1\t1\t2\t3\t0\t0\t10\t10\t91\tcreatives,'
      printf '%s\\n' '5\t1\t1\t1\t3\t1\t0\t0\t10\t10\t43\tthe13thclub.info@gmail.com'
      printf '%s\\n' '5\t1\t1\t1\t4\t1\t0\t0\t10\t10\t19\t(i'
      exit 0
      """)

      image_path = temp_image_path()
      File.write!(image_path, "image")

      assert {:ok, "Looking for creatives,\nthe13thclub.info@gmail.com"} == OCR.extract_text(image_path)
    end

    test "merges overlapping text from preprocessed story crops" do
      if System.find_executable("magick") do
        with_fake_tesseract("""
        #!/bin/sh
        printf '%s\\n' 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext'

        case "$1:$4" in
          *.ocr-*:6)
            printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t91\tcoffee,'
            printf '%s\\n' '5\t1\t1\t1\t1\t2\t0\t0\t10\t10\t92\tart,'
            printf '%s\\n' '5\t1\t1\t1\t1\t3\t0\t0\t10\t10\t92\tclothes,'
            printf '%s\\n' '5\t1\t1\t1\t1\t4\t0\t0\t10\t10\t91\tlunch'
            ;;
          *.ocr-*:11)
            printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t58\tbagels,'
            printf '%s\\n' '5\t1\t1\t1\t1\t2\t0\t0\t10\t10\t37\tcoffee,'
            printf '%s\\n' '5\t1\t1\t1\t1\t3\t0\t0\t10\t10\t92\tart,'
            ;;
          *)
            printf '%s\\n' '5\t1\t1\t1\t1\t1\t0\t0\t10\t10\t88\tsaturday'
            ;;
        esac

        exit 0
        """)

        image_path = valid_temp_image_path()

        assert {:ok, "saturday\nbagels, coffee, art, clothes, lunch"} == OCR.extract_text(image_path)
      end
    end

    test "returns tesseract failures with status and output" do
      with_fake_tesseract("""
      #!/bin/sh
      echo "image unreadable" >&2
      exit 1
      """)

      image_path = temp_image_path()
      File.write!(image_path, "image")

      assert {:error, {:ocr_failed, 1, "image unreadable"}} == OCR.extract_text(image_path)
    end

    @tag :external
    test "extracts text from a real image when tesseract is installed" do
      if OCR.available?() do
        path = Path.expand("../../test/support/fixtures/ocr_test.png", __DIR__)

        if File.exists?(path) do
          assert {:ok, text} = OCR.extract_text(path)
          assert is_binary(text)
        end
      end
    end
  end

  defp with_fake_tesseract(contents) do
    previous_path = System.get_env("PATH", "")
    directory = Path.join(System.tmp_dir!(), "instabot_ocr_#{System.unique_integer([:positive])}")
    executable = Path.join(directory, "tesseract")

    File.mkdir_p!(directory)
    File.write!(executable, contents)
    File.chmod!(executable, 0o755)

    System.put_env("PATH", "#{directory}:#{previous_path}")

    on_exit(fn ->
      System.put_env("PATH", previous_path)
      File.rm_rf(directory)
    end)
  end

  defp temp_image_path do
    Path.join(System.tmp_dir!(), "instabot_ocr_image_#{System.unique_integer([:positive])}.png")
  end

  defp valid_temp_image_path do
    image_path = temp_image_path()
    {_output, 0} = System.cmd("magick", ["-size", "20x20", "xc:white", image_path])
    image_path
  end
end
