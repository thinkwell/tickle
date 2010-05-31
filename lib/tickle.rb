#=============================================================================
#
#  Name:       Tickle
#  Author:     Joshua Lippiner
#  Purpose:    Parse natural language into recuring intervals
#
#=============================================================================


$LOAD_PATH.unshift(File.dirname(__FILE__))     # For use/testing when no gem is installed



require 'date'
require 'time'
require 'chronic'

class Symbol
  def <=>(with)
    return nil unless with.is_a? Symbol
    to_s <=> with.to_s
  end unless method_defined? :"<=>"
end

class Date
  def to_date
    self
  end unless method_defined?(:to_date)
  
  def to_time(form = :local)
    Time.send("#{form}_time", year, month, day)
  end
end

class Time
  class << self
    # Overriding case equality method so that it returns true for ActiveSupport::TimeWithZone instances
    def ===(other)
      other.is_a?(::Time)
    end
  
    # Return the number of days in the given month.
    # If no year is specified, it will use the current year.
    def days_in_month(month, year = now.year)
      return 29 if month == 2 && ::Date.gregorian_leap?(year)
      COMMON_YEAR_DAYS_IN_MONTH[month]
    end
  
    # Returns a new Time if requested year can be accommodated by Ruby's Time class
    # (i.e., if year is within either 1970..2038 or 1902..2038, depending on system architecture);
    # otherwise returns a DateTime
    def time_with_datetime_fallback(utc_or_local, year, month=1, day=1, hour=0, min=0, sec=0, usec=0)
      time = ::Time.send(utc_or_local, year, month, day, hour, min, sec, usec)
      # This check is needed because Time.utc(y) returns a time object in the 2000s for 0 <= y <= 138.
      time.year == year ? time : ::DateTime.civil_from_format(utc_or_local, year, month, day, hour, min, sec)
    rescue
      ::DateTime.civil_from_format(utc_or_local, year, month, day, hour, min, sec)
    end
  
    # Wraps class method +time_with_datetime_fallback+ with +utc_or_local+ set to <tt>:utc</tt>.
    def utc_time(*args)
      time_with_datetime_fallback(:utc, *args)
    end
  
    # Wraps class method +time_with_datetime_fallback+ with +utc_or_local+ set to <tt>:local</tt>.
    def local_time(*args)
      time_with_datetime_fallback(:local, *args)
    end
  end
  
  def to_date
     Date.new(self.year, self.month, self.day)
  end unless method_defined?(:to_date)
   
  def to_time
     self
  end
end

require 'tickle/tickle'
require 'tickle/handler'
require 'tickle/repeater'

module Tickle #:nodoc:
  VERSION = "0.1.7"

  def self.debug=(val); @debug = val; end

  def self.dwrite(msg, line_feed=nil)
    (line_feed ? p(">> #{msg}") : puts(">> #{msg}")) if @debug
  end

  def self.is_date(str)
    begin
      Date.parse(str.to_s)
      return true
    rescue Exception => e
      return false
    end
  end
end

class Date #:nodoc:
  # returns the days in the sending month
  def days_in_month
    d,m,y = mday,month,year
    d += 1 while Date.valid_civil?(y,m,d)
    d - 1
  end

  def bump(attr, amount=nil)
    amount ||= 1
    case attr
    when :day then
      Date.civil(self.year, self.month, self.day + amount)
    when :wday then
      amount = Date::ABBR_DAYNAMES.index(amount) if amount.is_a?(String)
      raise Exception, "specified day of week invalid.  Use #{Date::ABBR_DAYNAMES}" unless amount
      diff = (amount > self.wday) ? (amount - self.wday) : (7 - (self.wday - amount))
      Date.civil(self.year, self.month, self.day + diff)
    when :week then
      Date.civil(self.year, self.month, self.day + (7*amount))
    when :month then
      Date.civil(self.year, self.month+amount, self.day)
    when :year then
      Date.civil(self.year + amount, self.month, self.day)
    else
            raise Exception, "type \"#{attr}\" not supported."
    end
  end
  
  
end

class Time #:nodoc:
  def bump(attr, amount=nil)
    amount ||= 1
    case attr
    when :sec then
      Time.local(self.year, self.month, self.day, self.hour, self.min, self.sec + amount)
    when :min then
      Time.local(self.year, self.month, self.day, self.hour, self.min + amount, self.sec)
    when :hour then
      Time.local(self.year, self.month, self.day, self.hour + amount, self.min, self.sec)
    when :day then
      Time.local(self.year, self.month, self.day + amount, self.hour, self.min, self.sec)
    when :wday then
      amount = Time::RFC2822_DAY_NAME.index(amount) if amount.is_a?(String)
      raise Exception, "specified day of week invalid.  Use #{Time::RFC2822_DAY_NAME}" unless amount
      diff = (amount > self.wday) ? (amount - self.wday) : (7 - (self.wday - amount))
      Time.local(self.year, self.month, self.day + diff, self.hour, self.min, self.sec)
    when :week then
      Time.local(self.year, self.month, self.day + (amount * 7), self.hour, self.min, self.sec)
    when :month then
      Time.local(self.year, self.month + amount, self.day, self.hour, self.min, self.sec)
    when :year then
      Time.local(self.year + amount, self.month, self.day, self.hour, self.min, self.sec)
    else
      raise Exception, "type \"#{attr}\" not supported."
    end
  end
end

#class NilClass
#  def to_date
#    return nil
#  end unless method_defined?(:to_date)
#end

class String #:nodoc:
  # returns true if the sending string is a text or numeric ordinal (e.g. first or 1st)
  def is_ordinal?
    scanner = %w{first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twenty thirty thirtieth}
    regex = /\b(\d*)(st|nd|rd|th)\b/
    !(self =~ regex).nil? || scanner.include?(self.downcase)
  end

  def ordinal_as_number
    return self unless self.is_ordinal?
    scanner = {/first/ => '1st',
      /second/ => '2nd',
      /third/ => '3rd',
      /fourth/ => '4th',
      /fifth/ => '5th',
      /sixth/ => '6th',
      /seventh/ => '7th',
      /eighth/ => '8th',
      /ninth/ => '9th',
      /tenth/ => '10th',
      /eleventh/ => '11th',
      /twelfth/ => '12th',
      /thirteenth/ => '13th',
      /fourteenth/ => '14th',
      /fifteenth/ => '15th',
      /sixteenth/ => '16th',
      /seventeenth/ => '17th',
      /eighteenth/ => '18th',
      /nineteenth/ => '19th',
      /twentieth/ => '20th',
      /thirtieth/ => '30th',
    }
    result = self
    scanner.keys.each {|scanner_item| result = scanner[scanner_item] if scanner_item =~ self}
    return result.gsub(/\b(\d*)(st|nd|rd|th)\b/, '\1')
  end
end

class Array #:nodoc:
  # compares two arrays to determine if they both contain the same elements
  def same?(y)
    self.sort == y.sort
  end
end
