# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'logger'

module BOSS
  # module BOSSLogger
    @@BOSS_logger = Logger.new($stdout)

    # Set Logger::DEBUG for development
    @@BOSS_logger.level = Logger::DEBUG
    ##
    # Defining class variable "@@logger" to log errors, info and warning messages.
    def self.BOSS_logger
      @@BOSS_logger
    end
  # end
end
