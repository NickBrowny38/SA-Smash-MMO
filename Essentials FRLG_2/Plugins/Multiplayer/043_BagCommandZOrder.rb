module UIHelper
  class << self
    alias mmo_bag_pbShowCommands pbShowCommands unless method_defined?(:mmo_bag_pbShowCommands)

    def pbShowCommands(helpwindow, helptext, commands, initcmd = 0)
      ret = -1
      oldvisible  =  helpwindow.visible
      helpwindow.visible        = helptext ? true : false
      helpwindow.letterbyletter = false
      helpwindow.text           = helptext || ''
      cmdwindow = Window_CommandPokemon.new(commands)
      cmdwindow.index = initcmd
      begin
        cmdwindow.viewport  =  helpwindow.viewport

        cmdwindow.z = 300001
        helpwindow.z = 300000

        pbBottomRight(cmdwindow)
        helpwindow.resizeHeightToFit(helpwindow.text, Graphics.width - cmdwindow.width)
        pbBottomLeft(helpwindow)
        loop do          Graphics.update
          Input.update
          yield
          cmdwindow.update
          if Input.trigger?(Input::BACK)
            ret  =  -1
            pbPlayCancelSE
            break
          end
          if Input.trigger?(Input::USE)
            ret = cmdwindow.index
            pbPlayDecisionSE
            break
          end
        end
      ensure
        cmdwindow&.dispose
        helpwindow.visible = oldvisible
      end
      return ret
    end
  end
end

puts "[Bag Command Z-Order] Command window will render in front of bag UI"
