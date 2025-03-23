local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("NotificarJogador")

local ultimaNotificacaoId = nil

remote.OnClientEvent:Connect(function(titulo, mensagem)
	-- Não mostrar "Ocultar"
	if titulo == "Ocultar" then return end

	local id = HttpService:GenerateGUID(false)
	ultimaNotificacaoId = id

	local duracao = 60 -- tempo padrão

	-- Se for "Resultado", mostrar por 2 segundos e cancelar
	if titulo == "Resultado" then
		duracao = 10
		game.StarterGui:SetCore("SendNotification", {
			Title = titulo,
			Text = mensagem,
			Duration = duracao,
			NotificationId = id
		})

		task.delay(2, function()
			pcall(function()
				game.StarterGui:SetCore("CancelNotification", id)
			end)
		end)

	else
		-- Mostra pergunta ou aguardando e mantém por 60s
		game.StarterGui:SetCore("SendNotification", {
			Title = titulo,
			Text = mensagem,
			Duration = duracao,
			NotificationId = id
		})
	end
end)
