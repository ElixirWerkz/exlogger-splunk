defmodule ExLogger.Splunk.Mixfile do
  use Mix.Project

  def project do
    [ app: :exlogger_splunk,
      version: "0.0.1",
      elixir: ">= 0.10.3",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [applications: %w(exlogger jsex hackney)a]
  end

  defp deps do
    [
      {:exlogger, github: "ElixirWerkz/exlogger"},
      {:jsex,     github: "talentdeficit/jsex"},
      {:hackney,  github: "benoitc/hackney"},
    ]
  end
end
